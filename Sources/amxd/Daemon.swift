import AMXCore
import Dispatch
import Foundation
import GRDB
import os

final class Daemon: @unchecked Sendable {
    private static let teamIDBudget = 30
    private static let rollupEvery = 12

    private let db: DatabaseQueue
    private let writer: SampleWriter
    private let processes = ProcessSampler()
    private let system = SystemSampler()
    private let nettop = NettopStream()
    private let queue = DispatchQueue(label: AMX.daemonLabel)
    private let log = Logger(subsystem: AMX.daemonLabel, category: "tick")
    private let xpc: Bool
    private let dbPath: String
    private var listener: NSXPCListener?
    private var xpcService: XPCService?
    /// Team ID per executable path; nil means unsigned or no team.
    private var teamIDs: [String: String?] = [:]
    private var ticks = 0
    private var timer: DispatchSourceTimer?
    private var sigterm: DispatchSourceSignal?

    init(dbPath: String, xpc: Bool) throws {
        umask(0o022)
        try FileManager.default.createDirectory(
            atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        db = try Store.openWriter(path: dbPath)
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_autocheckpoint=0") }
        writer = SampleWriter(db: db, path: dbPath)
        self.xpc = xpc
        self.dbPath = dbPath
    }

    func run() -> Never {
        nettop.start()
        if xpc { startXPC() }

        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        term.setEventHandler { [self] in
            timer?.cancel()
            nettop.stop()
            checkpoint()
            exit(0)
        }
        term.resume()
        sigterm = term

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: AMX.tick)
        t.setEventHandler { [self] in tick() }
        t.resume()
        timer = t
        dispatchMain()
    }

    private func startXPC() {
        let service = XPCService(dbPath: dbPath)
        let l = NSXPCListener(machServiceName: AMX.daemonLabel)
        l.delegate = service // weak; xpcService keeps it alive
        l.resume()
        xpcService = service
        listener = l
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        let sampled = processes.sample(now: now, gpuNanos: GPUReader.processNanos())
        var samples = sampled.samples
        var sys = system.sample(now: now)

        let rates = nettop.rates(alive: Dictionary(samples.map { ($0.identity.pid, $0.identity) }, uniquingKeysWith: { $1 }))
        for i in samples.indices {
            guard let r = rates[samples[i].identity.pid] else { continue }
            samples[i].netIn = r.inPerSec
            samples[i].netOut = r.outPerSec
        }
        sys.netIn = rates.values.reduce(0) { $0 + $1.inPerSec }
        sys.netOut = rates.values.reduce(0) { $0 + $1.outPerSec }

        var budget = Self.teamIDBudget
        let attributed = sampled.new.map { raw -> (RawProcess, AppInfo, teamID: String?) in
            let app = AppAttribution.app(forExecutable: raw.path, processName: raw.name)
            var team: String?
            // Over budget: written without a team ID (no backfill in M1).
            if let path = raw.path {
                if let cached = teamIDs[path] {
                    team = cached
                } else if budget > 0 {
                    budget -= 1
                    if teamIDs.count >= 4096 { teamIDs.removeAll() }
                    team = CodeSigning.teamID(forPath: path)
                    teamIDs[path] = team
                }
            }
            return (raw, app, team)
        }

        do {
            try writer.write(now: now, processes: samples, newProcesses: attributed, system: sys)
        } catch {
            log.error("write failed: \(String(describing: error), privacy: .public)")
        }

        ticks += 1
        if ticks % Self.rollupEvery == 0 {
            do {
                try Rollup.run(db: db, now: now, policy: RetentionPolicy())
            } catch {
                log.error("rollup failed: \(String(describing: error), privacy: .public)")
            }
            checkpoint()
        }
    }

    private func checkpoint() {
        do {
            let row = try db.writeWithoutTransaction { try Row.fetchOne($0, sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
            // Busy: a reader blocked the checkpoint and the WAL keeps growing until one succeeds.
            if let row, row[0] as Int != 0 {
                log.error("""
                    checkpoint busy: log \(row[1] as Int, privacy: .public) frames, \
                    checkpointed \(row[2] as Int, privacy: .public)
                    """)
            }
        } catch {
            log.error("checkpoint failed: \(String(describing: error), privacy: .public)")
        }
    }
}
