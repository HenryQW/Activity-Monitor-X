import AMXCore
import Dispatch
import Foundation
import GRDB
import os

final class Daemon: @unchecked Sendable {
    /// On-demand 1 s sampling. Own samplers, because CPU and disk rates are deltas per sampler instance.
    private struct Live {
        let processes = ProcessSampler()
        let system = SystemSampler()
        var apps: [ProcessIdentity: (name: String, path: String?, app: AppInfo)] = [:]
        var primed = false
        var latest: (ts: Double, json: Data)?
    }

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
    private var live = Live()
    private var liveDemand = LiveDemand()
    private var liveTimer: DispatchSourceTimer?
    /// Network rates of the last recording tick; live rows reuse them (nettop emits every 5 s).
    private var latestNet: [ProcessIdentity: (inPerSec: Double, outPerSec: Double)] = [:]

    init(dbPath: String, xpc: Bool) throws {
        umask(0o022)
        try FileManager.default.createDirectory(
            atPath: (dbPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        db = try Store.openWriter(path: dbPath)
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_autocheckpoint=0") }
        writer = try SampleWriter(db: db, path: dbPath, ticksPerCommit: AMX.ticksPerCommit)
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
            flush()
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
        let service = XPCService(dbPath: dbPath, live: { [self] in queue.sync { liveSnapshot() } })
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
        var net: [ProcessIdentity: (inPerSec: Double, outPerSec: Double)] = [:]
        for i in samples.indices {
            guard let r = rates[samples[i].identity.pid] else { continue }
            samples[i].netIn = r.inPerSec
            samples[i].netOut = r.outPerSec
            net[samples[i].identity] = r
        }
        latestNet = net
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
            flush()  // the rollup reads every tick so far
            do {
                try Rollup.run(db: db, now: now, policy: RetentionPolicy())
            } catch {
                log.error("rollup failed: \(String(describing: error), privacy: .public)")
            }
        }
        if ticks % AMX.ticksPerCheckpoint == 0 { checkpoint() }
    }

    private func flush() {
        do {
            try writer.flush()
        } catch {
            log.error("write failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Called on `queue`. Keeps live sampling on and returns the latest snapshot unless it is stale.
    private func liveSnapshot() -> Data? {
        let now = Date().timeIntervalSince1970
        liveDemand.requested(at: now)
        if liveTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1)
            t.setEventHandler { [self] in liveTick() }
            t.resume()
            liveTimer = t
        }
        guard let latest = live.latest, now - latest.ts < 3 else { return nil }
        return latest.json
    }

    /// Never writes the DB.
    private func liveTick() {
        let now = Date().timeIntervalSince1970
        guard liveDemand.shouldSample(now: now) else {
            liveTimer?.cancel()
            liveTimer = nil
            live = Live()  // the next session primes fresh
            return
        }
        let sampled = live.processes.sample(now: now, gpuNanos: GPUReader.processNanos())
        let sys = live.system.sample(now: now)
        for raw in sampled.new {
            live.apps[raw.identity] = (raw.name, raw.path, AppAttribution.app(forExecutable: raw.path, processName: raw.name))
        }
        let alive = Set(sampled.samples.map(\.identity))
        live.apps = live.apps.filter { alive.contains($0.key) }
        // The first sample has no previous counters, so its rates are all 0.
        guard live.primed else {
            live.primed = true
            return
        }

        let rows = sampled.samples.compactMap { s -> LiveProcess? in
            guard let (name, path, app) = live.apps[s.identity] else { return nil }
            let net = latestNet[s.identity]
            return LiveProcess(pid: s.identity.pid, startTime: s.identity.startTime, name: name,
                               appKey: app.appPath ?? name, appName: app.appName, path: path, cpu: s.cpu, mem: s.mem,
                               diskR: s.diskR, diskW: s.diskW, netIn: net?.inPerSec ?? 0,
                               netOut: net?.outPerSec ?? 0, gpu: s.gpu, energy: s.energy)
        }
        let snapshot = LiveSnapshot(ts: now, system: LiveSystem(cpu: sys.cpu, memUsed: sys.memUsed,
                                                                pressureLevel: sys.pressureLevel,
                                                                thermalState: sys.thermalState),
                                    processes: rows)
        do {
            live.latest = (now, try JSONEncoder().encode(snapshot))
        } catch {
            log.error("live encode failed: \(String(describing: error), privacy: .public)")
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
