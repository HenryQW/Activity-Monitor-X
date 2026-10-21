import Foundation
import GRDB

/// Writes one tick per `write` call in a single transaction. Process rows are sparse:
/// a row is stored only when it changed enough, or once per minute as a heartbeat.
public final class SampleWriter {
    private struct Last {
        var ts: Double
        var cpu: Double, mem: UInt64, gpu: Double
        var diskR: Double, diskW: Double, netIn: Double, netOut: Double
    }

    private let db: DatabaseQueue
    private let path: String
    private var ids: [ProcessIdentity: Int64] = [:]
    private var last: [ProcessIdentity: Last] = [:]
    private var lastSeenBucket: [ProcessIdentity: Int] = [:]
    private var lastPressure: Int?
    private var lastThermal: Int?

    public init(db: DatabaseQueue, path: String) {
        self.db = db
        self.path = path
    }

    public func write(now: Double, processes: [ProcessSample],
                      newProcesses: [(RawProcess, AppInfo, teamID: String?)], system: SystemSample) throws {
        // State is applied only after the transaction commits.
        var newIds = ids, newLast = last, newBuckets = lastSeenBucket
        let bucket = Int((now / 60).rounded(.down))
        do {
            try db.write { db in
                for (raw, app, teamID) in newProcesses {
                    var record = ProcessRecord(
                        pid: raw.identity.pid, startTime: raw.identity.startTime, name: raw.name, path: raw.path,
                        appPath: app.appPath, appName: app.appName, bundleId: app.bundleID, teamId: teamID,
                        uid: Int64(raw.uid), translated: raw.translated, firstSeen: now, lastSeen: now)
                    try record.insert(db, onConflict: .ignore)
                    // An ignored insert can leave a stale rowid in `record`, so always look it up.
                    newIds[raw.identity] = try Self.fetchId(db, raw.identity)
                    newBuckets[raw.identity] = bucket
                }
                for p in processes {
                    guard let id = newIds[p.identity] else { continue }
                    if newBuckets[p.identity] != bucket {
                        try ProcessRecord.filter(Column("id") == id).updateAll(db, Column("last_seen").set(to: now))
                        newBuckets[p.identity] = bucket
                    }
                    guard Self.shouldWrite(p, last: newLast[p.identity], now: now) else { continue }
                    try ProcessSampleRecord(processId: id, ts: now, cpu: p.cpu, mem: Int64(p.mem), diskR: p.diskR,
                                            diskW: p.diskW, energy: p.energy, gpu: p.gpu,
                                            netIn: p.netIn, netOut: p.netOut).insert(db)
                    newLast[p.identity] = Last(ts: now, cpu: p.cpu, mem: p.mem, gpu: p.gpu, diskR: p.diskR,
                                               diskW: p.diskW, netIn: p.netIn, netOut: p.netOut)
                }
                try Self.record(system, now: now).insert(db)
                try events(system, now: now, processes: processes, ids: newIds).forEach { var e = $0; try e.insert(db) }
            }
        } catch {
            throw StoreError(path: path, underlying: error)
        }
        ids = newIds
        last = newLast
        lastSeenBucket = newBuckets
        lastPressure = system.pressureLevel
        lastThermal = system.thermalState
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
    private func events(_ s: SystemSample, now: Double, processes: [ProcessSample],
                        ids: [ProcessIdentity: Int64]) -> [EventRecord] {
        var out: [EventRecord] = []
        if let lastPressure, lastPressure != s.pressureLevel {
            let top = processes.max { $0.mem < $1.mem }.flatMap { ids[$0.identity] }
            let word = [1: "normal", 2: "warning", 4: "critical"][s.pressureLevel] ?? "level \(s.pressureLevel)"
            out.append(EventRecord(ts: now, kind: "pressure", severity: [1: 0, 2: 1, 4: 2][s.pressureLevel] ?? 0,
                                   processId: top, message: "Memory pressure \(word)", value: s.pressurePct))
        }
        if let lastThermal, lastThermal != s.thermalState {
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
