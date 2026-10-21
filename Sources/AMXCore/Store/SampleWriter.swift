import Foundation
import GRDB

/// Writes `ticksPerCommit` ticks per transaction: each commit rewrites the last page of every table it
/// touches, so commits, not rows, set the bytes written. `flush` commits the ticks so far. Process rows
/// are sparse: a row is stored only when it changed enough, or once per minute as a heartbeat.
///
/// `processes.last_seen` is `Schema.open` while a process lives; when it ends, it becomes the first tick
/// of the last minute it was seen. Updating it every minute for every live process rewrote most of
/// `processes`. Ends are written with the first tick of the next minute: until then readers take an open
/// process to the first tick of the writer's last minute, which is the same value.
public final class SampleWriter {
    private struct Last {
        var ts: Double
        var cpu: Double, mem: UInt64, gpu: Double
        var diskR: Double, diskW: Double, netIn: Double, netOut: Double
    }

    private struct Tick {
        let now: Double
        let processes: [ProcessSample]
        let newProcesses: [(RawProcess, AppInfo, teamID: String?)]
        let system: SystemSample
    }

    /// What the next tick compares against; applied only after its transaction commits.
    private struct State {
        var ids: [ProcessIdentity: Int64] = [:]
        var last: [ProcessIdentity: Last] = [:]
        /// The first tick of the latest minute each process was seen: its `last_seen` once it ends.
        var lastSeen: [ProcessIdentity: Double] = [:]
        /// `last_seen` of the processes that ended in the minute of the last tick, by id.
        var ended: [Int64: Double] = [:]
        var minute: Int?
        var pressure: Int?
        var thermal: Int?
    }

    private let db: DatabaseQueue
    private let path: String
    private let ticksPerCommit: Int
    private var state = State()
    private var queued: [Tick] = []
    /// New processes of a failed write; the sampler reports a process as new only once.
    private var pending: [ProcessIdentity: (RawProcess, AppInfo, teamID: String?)] = [:]
    var ids: [ProcessIdentity: Int64] { state.ids }

    /// Closes the processes a previous writer left open at that writer's last minute; the ones still
    /// alive reopen on their first write.
    public init(db: DatabaseQueue, path: String, ticksPerCommit: Int = 1) throws {
        self.db = db
        self.path = path
        self.ticksPerCommit = ticksPerCommit
        do {
            try db.write { db in
                try db.execute(sql: """
                    UPDATE processes SET last_seen = MAX(first_seen, IFNULL(\(Schema.lastMinuteSQL), first_seen))
                    WHERE last_seen = ?
                    """, arguments: [Schema.open])
            }
        } catch {
            throw StoreError(path: path, underlying: error)
        }
    }

    public func write(now: Double, processes: [ProcessSample],
                      newProcesses: [(RawProcess, AppInfo, teamID: String?)], system: SystemSample) throws {
        queued.append(Tick(now: now, processes: processes, newProcesses: newProcesses, system: system))
        if queued.count >= ticksPerCommit { try flush() }
    }

    public func flush() throws {
        guard let lastTick = queued.last else { return }
        let ticks = queued
        queued = []
        var next = state
        do {
            try db.write { db in
                var carried = pending
                for tick in ticks {
                    try apply(tick, carrying: carried, to: &next, db)
                    carried = [:]
                }
            }
        } catch {
            let live = Set(lastTick.processes.map(\.identity))
            for n in ticks.flatMap(\.newProcesses) { pending[n.0.identity] = n }
            pending = pending.filter { live.contains($0.key) }
            throw StoreError(path: path, underlying: error)
        }
        pending = [:]
        state = next
    }

    private func apply(_ tick: Tick, carrying pending: [ProcessIdentity: (RawProcess, AppInfo, teamID: String?)],
                       to s: inout State, _ db: Database) throws {
        let now = tick.now
        let bucket = Int((now / 60).rounded(.down))
        let live = Set(tick.processes.map(\.identity))
        var inserts = pending.filter { live.contains($0.key) }
        for n in tick.newProcesses { inserts[n.0.identity] = n }
        for (identity, id) in s.ids where !live.contains(identity) { s.ended[id] = s.lastSeen[identity]! }
        for (raw, app, teamID) in inserts.values {
            let record = ProcessRecord(
                pid: raw.identity.pid, startTime: raw.identity.startTime, name: raw.name, path: raw.path,
                appPath: app.appPath, appName: app.appName, bundleId: app.bundleID, teamId: teamID,
                uid: Int64(raw.uid), translated: raw.translated, firstSeen: now, lastSeen: Schema.open)
            try record.insert(db, onConflict: .ignore)
            // An ignored insert can leave a stale rowid in `record`, so always look it up.
            guard let id = try Self.fetchId(db, raw.identity) else { continue }
            // Seen by an earlier writer, which closed it.
            try ProcessRecord.filter(key: id).filter(Column("last_seen") != Schema.open)
                .updateAll(db, Column("last_seen").set(to: Schema.open))
            s.ids[raw.identity] = id
            s.lastSeen[raw.identity] = now
            s.ended[id] = nil
        }
        if bucket != s.minute {
            for (id, seen) in s.ended {
                try ProcessRecord.filter(key: id).updateAll(db, Column("last_seen").set(to: seen))
            }
            s.ended = [:]
        }
        for p in tick.processes {
            guard let id = s.ids[p.identity] else { continue }
            if let seen = s.lastSeen[p.identity], Int((seen / 60).rounded(.down)) != bucket {
                s.lastSeen[p.identity] = now
            }
            guard Self.shouldWrite(p, last: s.last[p.identity], now: now) else { continue }
            try ProcessSampleRecord(processId: id, ts: now, cpu: p.cpu, mem: Int64(p.mem), diskR: p.diskR,
                                    diskW: p.diskW, energy: p.energy, gpu: p.gpu,
                                    netIn: p.netIn, netOut: p.netOut).insert(db)
            s.last[p.identity] = Last(ts: now, cpu: p.cpu, mem: p.mem, gpu: p.gpu, diskR: p.diskR,
                                      diskW: p.diskW, netIn: p.netIn, netOut: p.netOut)
        }
        try Self.record(tick.system, now: now).insert(db)
        try Self.events(tick.system, now: now, processes: tick.processes, state: s).forEach { try $0.insert(db) }
        s.minute = bucket
        s.ids = s.ids.filter { live.contains($0.key) }
        s.last = s.last.filter { live.contains($0.key) }
        s.lastSeen = s.lastSeen.filter { live.contains($0.key) }
        s.pressure = tick.system.pressureLevel
        s.thermal = tick.system.thermalState
    }

    private static func fetchId(_ db: Database, _ identity: ProcessIdentity) throws -> Int64? {
        try ProcessRecord.filter(Column("pid") == identity.pid && Column("start_time") == identity.startTime)
            .fetchOne(db)?.id
    }

    private static func shouldWrite(_ p: ProcessSample, last: Last?, now: Double) -> Bool {
        guard let last else { return true }
        if (now / 60).rounded(.down) != (last.ts / 60).rounded(.down) { return true }
        if abs(p.cpu - last.cpu) > 0.5 || abs(p.gpu - last.gpu) > 0.5 { return true }
        if abs(Double(p.mem) - Double(last.mem)) > 524_288 { return true }
        return ioChanged(p.diskR, last.diskR) || ioChanged(p.diskW, last.diskW)
            || ioChanged(p.netIn, last.netIn) || ioChanged(p.netOut, last.netOut)
    }

    private static func ioChanged(_ new: Double, _ old: Double) -> Bool {
        (new == 0) != (old == 0) || abs(new - old) > 1024
    }

    private static func record(_ s: SystemSample, now: Double) -> SystemSampleRecord {
        SystemSampleRecord(ts: now, cpu: s.cpu, memUsed: Int64(s.memUsed), memCompressed: Int64(s.memCompressed),
                           swapUsed: Int64(s.swapUsed), pressureLevel: Int64(s.pressureLevel),
                           pressurePct: s.pressurePct, thermalState: Int64(s.thermalState), load1: s.load1,
                           diskR: s.diskR, diskW: s.diskW, diskIops: s.diskIOPS, diskLatMs: s.diskLatMs,
                           diskUtil: s.diskUtil, gpu: s.gpu, tempCpu: s.tempCPU, tempGpu: s.tempGPU,
                           tempSsd: s.tempSSD, netIn: s.netIn, netOut: s.netOut)
    }

    /// Events fire on change from the last written level; the first tick only sets the baseline.
    private static func events(_ s: SystemSample, now: Double, processes: [ProcessSample],
                               state: State) -> [EventRecord] {
        var out: [EventRecord] = []
        if let lastPressure = state.pressure, lastPressure != s.pressureLevel {
            let top = processes.max { $0.mem < $1.mem }.flatMap { state.ids[$0.identity] }
            let word = [1: "normal", 2: "warning", 4: "critical"][s.pressureLevel] ?? "level \(s.pressureLevel)"
            out.append(EventRecord(ts: now, kind: "pressure", severity: [1: 0, 2: 1, 4: 2][s.pressureLevel] ?? 0,
                                   processId: top, message: "Memory pressure \(word)", value: s.pressurePct))
        }
        if let lastThermal = state.thermal, lastThermal != s.thermalState {
            let word = ["nominal", "fair", "serious", "critical"][safe: s.thermalState] ?? "state \(s.thermalState)"
            out.append(EventRecord(ts: now, kind: "thermal", severity: s.thermalState,
                                   message: "Thermal state \(word)", value: Double(s.thermalState)))
        }
        return out
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
