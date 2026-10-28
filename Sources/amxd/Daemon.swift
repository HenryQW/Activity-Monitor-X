import AMXCore
import Dispatch
import Foundation
import GRDB
import os

final class Daemon: @unchecked Sendable {
    /// On-demand 1 s sampling. Own samplers, because CPU and disk rates are deltas per sampler instance.
    private struct Live {
        let processes = ProcessSampler()
        let system = SystemSampler(liveOnly: true)
        var apps: [ProcessIdentity: (name: String, path: String?, uid: UInt32, app: AppInfo)] = [:]
        var primed = false
        /// `uptime` is `systemUptime`, so a wall clock step does not make the snapshot stale or fresh.
        var latest: (uptime: Double, json: Data)?
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
    private var backfill = TeamIDBackfill()
    private var engine = EventEngine()
    private let settingsURL = URL(fileURLWithPath: AMX.settingsPath)
    /// Read and replaced on `queue` only.
    private var settings = DaemonSettings()
    private var ticks = 0
    private var primed = false
    /// New processes of the first tick, which is not written.
    private var firstNew: [RawProcess] = []
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
        writer = SampleWriter(db: db, path: dbPath, ticksPerCommit: AMX.ticksPerCommit)
        self.xpc = xpc
        self.dbPath = dbPath
        do {
            settings = try DaemonSettings.load(from: settingsURL)
        } catch {
            // The file stays as it is until the next accepted setSettings replaces it.
            log.error("settings not applied, using defaults: \(error.localizedDescription, privacy: .public)")
        }
        do {
            backfill.enqueue(try writer.pathsWithoutTeamID())
        } catch {
            log.error("backfill scan failed: \(String(describing: error), privacy: .public)")
        }
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
        t.schedule(deadline: .now(), repeating: AMX.tick, leeway: .milliseconds(500))
        t.setEventHandler { [self] in tick() }
        t.resume()
        timer = t
        dispatchMain()
    }

    private func startXPC() {
        let service = XPCService(dbPath: dbPath, live: { [self] in queue.sync { liveSnapshot() } },
                                 settings: { [self] in queue.sync { try! settings.encoded() } },
                                 setSettings: { [self] json in queue.sync { applySettings(json) } })
        let l = NSXPCListener(machServiceName: AMX.daemonLabel)
        l.delegate = service // weak; xpcService keeps it alive
        l.resume()
        xpcService = service
        listener = l
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        let sampled = processes.sample(gpuNanos: GPUReader.processNanos())
        var samples = sampled.samples
        var sys = system.sample()
        // The first sample has no previous counters, so its rates are all 0: write from the second tick on.
        guard primed else {
            primed = true
            firstNew = sampled.new
            return
        }
        // The sampler reports a process as new only once, so the first tick's new processes still running come now.
        let alive = Set(samples.map(\.identity))
        let new = firstNew.filter { alive.contains($0.identity) } + sampled.new
        firstNew = []

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
        let attributed = new.map { raw -> (RawProcess, AppInfo, teamID: String?) in
            let app = attribute(raw)
            var team: String?
            // Over budget: written without a team ID, which the backfill fills in later.
            if let path = raw.path {
                if let cached = teamIDs[path] {
                    team = cached
                } else if budget > 0 {
                    budget -= 1
                    team = resolveTeamID(path)
                } else {
                    backfill.enqueue([path])
                }
            }
            return (raw, app, team)
        }

        let events = engine.evaluate(now: now, processes: samples, new: attributed.map { ($0.0, $0.1) },
                                     system: sys, rules: settings.rules)
        do {
            try writer.write(now: now, processes: samples, newProcesses: attributed, system: sys, events: events)
        } catch {
            log.error("write failed: \(String(describing: error), privacy: .public)")
        }

        // Unused budget. A cached path still takes a slot but needs no lookup, so no path is looked up twice.
        var found: [String: String] = [:]
        for path in backfill.take(budget) {
            if let team = teamIDs[path] ?? resolveTeamID(path) { found[path] = team }
        }
        if !found.isEmpty { writer.backfillTeamIDs(found) }

        ticks += 1
        if ticks % Self.rollupEvery == 0 {
            flush()  // the rollup reads every tick so far
            do {
                var policy = RetentionPolicy()
                policy.maxBytes = settings.sizeCapBytes
                try Rollup.run(db: db, now: now, policy: policy)
            } catch {
                log.error("rollup failed: \(String(describing: error), privacy: .public)")
            }
        }
        if ticks % AMX.ticksPerCheckpoint == 0 { checkpoint() }
    }

    /// Called on `queue`. Rules and terminals apply from the next tick, the size cap at the next rollup; nil on success, else the problem, with file and settings unchanged.
    private func applySettings(_ json: Data) -> String? {
        do {
            let new = try DaemonSettings.decodeValidated(json)
            try new.save(to: settingsURL)
            settings = new
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func resolveTeamID(_ path: String) -> String? {
        if teamIDs.count >= 4096 { teamIDs.removeAll() }
        let team = CodeSigning.teamID(forPath: path)
        teamIDs[path] = team
        return team
    }

    /// Recording and Live share this rule. Rows already written keep their app (M3-D5).
    private func attribute(_ raw: RawProcess) -> AppInfo {
        AppAttribution.app(forExecutable: raw.path, processName: raw.name,
                           responsiblePath: Responsibility.responsiblePath(of: raw.identity.pid),
                           terminals: Set(settings.terminalBundleIDs))
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
        let uptime = ProcessInfo.processInfo.systemUptime
        liveDemand.requested(at: uptime)
        if liveTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
            t.setEventHandler { [self] in liveTick() }
            t.resume()
            liveTimer = t
        }
        guard let latest = live.latest, uptime - latest.uptime < 3 else { return nil }
        return latest.json
    }

    /// Never writes the DB.
    private func liveTick() {
        let now = Date().timeIntervalSince1970, uptime = ProcessInfo.processInfo.systemUptime
        guard liveDemand.shouldSample(now: uptime) else {
            liveTimer?.cancel()
            liveTimer = nil
            live = Live()  // the next session primes fresh
            return
        }
        let sampled = live.processes.sample(gpuNanos: GPUReader.processNanos())
        let sys = live.system.sample()
        for raw in sampled.new {
            live.apps[raw.identity] = (raw.name, raw.path, raw.uid, attribute(raw))
        }
        let alive = Set(sampled.samples.map(\.identity))
        live.apps = live.apps.filter { alive.contains($0.key) }
        // The first sample has no previous counters, so its rates are all 0.
        guard live.primed else {
            live.primed = true
            return
        }

        let rows = sampled.samples.compactMap { s -> LiveProcess? in
            guard let (name, path, uid, app) = live.apps[s.identity] else { return nil }
            let net = latestNet[s.identity]
            return LiveProcess(pid: s.identity.pid, startTime: s.identity.startTime, name: name,
                               appKey: app.appPath ?? name, appName: app.appName, path: path, cpu: s.cpu, mem: s.mem,
                               diskR: s.diskR, diskW: s.diskW, netIn: net?.inPerSec ?? 0,
                               netOut: net?.outPerSec ?? 0, gpu: s.gpu, energy: s.energy,
                               bundleID: app.bundleID, teamID: path.flatMap { teamIDs[$0] ?? nil }, uid: uid)
        }
        let snapshot = LiveSnapshot(ts: now, system: LiveSystem(cpu: sys.cpu, memUsed: sys.memUsed,
                                                                pressureLevel: sys.pressureLevel,
                                                                thermalState: sys.thermalState),
                                    processes: rows)
        do {
            live.latest = (uptime, try JSONEncoder().encode(snapshot))
        } catch {
            log.error("live encode failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func checkpoint() {
        do {
            // TRUNCATE waits the whole busy timeout for a reader, and this queue also serves Live, so wait 100 ms only.
            let row = try db.writeWithoutTransaction { db in
                let normal = try Int.fetchOne(db, sql: "PRAGMA busy_timeout")!
                try db.execute(sql: "PRAGMA busy_timeout=100")
                defer { try? db.execute(sql: "PRAGMA busy_timeout=\(normal)") }
                return try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
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
