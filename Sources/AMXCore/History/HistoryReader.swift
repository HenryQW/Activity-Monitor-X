import GRDB

public struct AppKey: Hashable, Sendable, Codable {
    public init(key: String, name: String) { (self.key, self.name) = (key, name) }
    public let key: String
    public let name: String
}

public struct Slice: Sendable {
    public let start: Double
    public let end: Double
    public let value: Double
    public let peak: Double

    public init(start: Double, end: Double, value: Double, peak: Double) {
        (self.start, self.end, self.value, self.peak) = (start, end, value, peak)
    }
}

public struct ProcessTrack: Sendable {
    public let processID: Int64
    public let pid: Int32
    /// With `pid`, the process identity: a pid alone can be reused.
    public let startTime: Double
    public let name: String
    public let app: AppKey
    /// Executable path; nil when unknown.
    public let path: String?
    /// `processes.last_seen` (written once a minute); for Live tracks, the ts of the last snapshot holding the process.
    public let lastSeen: Double
    public let slices: [Slice]

    public init(processID: Int64, pid: Int32, startTime: Double, name: String, app: AppKey, path: String? = nil,
                lastSeen: Double = 0, slices: [Slice]) {
        (self.processID, self.pid, self.startTime, self.name, self.app, self.path, self.lastSeen, self.slices)
            = (processID, pid, startTime, name, app, path, lastSeen, slices)
    }
}

public struct HistoryReader {
    public let pool: DatabasePool

    public init(pool: DatabasePool) { self.pool = pool }

    private struct Tier {
        let table: String, time: String, hold: Double
        let isRaw: Bool
    }

    public func tracks(range: HistoryRange, metric: Metric, end: Double) throws -> [ProcessTrack] {
        let tier: Tier
        switch range.source {
        case .live: preconditionFailure("live range is served over XPC, not the database")
        case .raw: tier = Tier(table: "process_samples", time: "ts", hold: 65, isRaw: true)
        case .minute: tier = Tier(table: "process_minute", time: "bucket", hold: 3660, isRaw: false)
        case .hour: tier = Tier(table: "process_hour", time: "bucket", hold: 90_000, isRaw: false)
        }
        // Raw rows carry no max; the peak of a raw value is the value.
        func sum(_ suffix: String) -> String {
            metric.columns.map { "IFNULL(t.\($0)\(suffix), 0)" }.joined(separator: " + ")
        }
        let value = sum(tier.isRaw ? "" : "_avg")
        let peak = tier.isRaw ? value : sum("_max")
        let start = end - range.seconds
        // A slice reaching `start` needs `last_seen + 60 > start`, so other processes are skipped.
        let metaSQL = """
            SELECT id, pid, start_time, name, app_path, app_name, first_seen, last_seen, path
            FROM processes WHERE last_seen > ? ORDER BY id
            """
        // In time order the index serves the order and each process folds its rows as they come:
        // no join and no sort over the (up to ~900k) rows.
        let sql = """
            SELECT t.process_id, t.\(tier.time), \(value), \(peak)
            FROM \(tier.table) t
            WHERE t.\(tier.time) >= ? AND t.\(tier.time) < ?
            ORDER BY t.\(tier.time)
            """
        struct Builder {
            let id: Int64, pid: Int32, startTime: Double, name: String, app: AppKey, path: String?, firstSeen: Double, lastSeen: Double
            var slices: [Slice] = []
            var last: (t: Double, v: Double, pk: Double)?
        }
        func close(_ b: inout Builder, next: Double) {
            guard let (t, v, pk) = b.last else { return }
            // A bucket row averages alive time only, so it starts no earlier than the process.
            let sliceStart = max(t, b.firstSeen, start)
            // Raw rows follow the rollup: a gap past the hold means the row covered one 5 s tick.
            let sliceEnd = tier.isRaw && next.isFinite
                ? min(next - t <= tier.hold ? next : t + 5, end)
                : min(next, t + tier.hold, b.lastSeen + 60, end)  // last_seen is written once per minute
            if sliceStart < sliceEnd { b.slices.append(Slice(start: sliceStart, end: sliceEnd, value: v, peak: pk)) }
        }
        // Stream with positional access: name-based Row copies dominated the 90-day query.
        var builders: [Builder] = []
        try pool.read { db in
            var slot: [Int64: Int] = [:]
            let metas = try Row.fetchCursor(db, sql: metaSQL, arguments: [start - 60])
            while let r = try metas.next() {
                let id: Int64 = r[0], name: String = r[3], appPath: String? = r[4], appName: String? = r[5]
                slot[id] = builders.count
                builders.append(Builder(id: id, pid: r[1], startTime: r[2], name: name,
                                        app: AppKey(key: appPath ?? name, name: appName ?? name),
                                        path: r[8], firstSeen: r[6], lastSeen: r[7]))
            }
            let rows = try Row.fetchCursor(db, sql: sql, arguments: [start - tier.hold, end])
            while let r = try rows.next() {
                guard let i = slot[r[0]] else { continue }
                let t: Double = r[1]
                close(&builders[i], next: t)
                builders[i].last = (t, r[2], r[3])
            }
        }
        var result: [ProcessTrack] = []
        for var b in builders {
            close(&b, next: .infinity)
            if !b.slices.isEmpty {
                result.append(ProcessTrack(processID: b.id, pid: b.pid, startTime: b.startTime, name: b.name,
                                           app: b.app, path: b.path, lastSeen: b.lastSeen, slices: b.slices))
            }
        }
        return result
    }
}

public struct SystemPoint: Sendable {
    public let bucket: Double
    public let cpu: Double
    public let memUsed: Double
    public let pressureLevel: Int
    public let thermalState: Int
}

public struct EventMark: Sendable {
    public let ts: Double
    public let kind: String
    public let severity: Int
    public let message: String
    public let app: AppKey?
}

extension HistoryReader {
    /// System tiers are dense, so each chart bucket averages the rows inside it; empty buckets are omitted.
    public func system(range: HistoryRange, end: Double) throws -> [SystemPoint] {
        let table: String, time: String, cpu: String, mem: String, pressure: String, thermal: String
        switch range.source {
        case .live: preconditionFailure("live range is served over XPC, not the database")
        case .raw:
            (table, time, cpu, mem, pressure, thermal) = ("system_samples", "ts", "cpu", "mem_used", "pressure_level", "thermal_state")
        case .minute, .hour:
            table = range.source == .minute ? "system_minute" : "system_hour"
            (time, cpu, mem, pressure, thermal) = ("bucket", "cpu_avg", "mem_used_avg", "pressure_level_max", "thermal_state_max")
        }
        let start = end - range.seconds
        let sql = """
            SELECT CAST((\(time) - ?1) / ?3 AS INTEGER) AS b,
                   AVG(\(cpu)) AS cpu, AVG(\(mem)) AS mem, MAX(\(pressure)) AS pressure, MAX(\(thermal)) AS thermal
            FROM \(table) WHERE \(time) >= ?1 AND \(time) < ?2
            GROUP BY b ORDER BY b
            """
        return try pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [start, end, range.chartBucket]).map {
                SystemPoint(bucket: start + Double($0["b"] as Int) * range.chartBucket,
                            cpu: $0["cpu"] ?? 0, memUsed: $0["mem"] ?? 0,
                            pressureLevel: $0["pressure"] ?? 0, thermalState: $0["thermal"] ?? 0)
            }
        }
    }

    public func events(from: Double, to: Double) throws -> [EventMark] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT e.ts, e.kind, e.severity, e.message, p.name, p.app_path, p.app_name
                FROM events e LEFT JOIN processes p ON p.id = e.process_id
                WHERE e.ts >= ? AND e.ts < ? ORDER BY e.ts, e.id
                """, arguments: [from, to]).map { row in
                let name: String? = row["name"]
                let app = name.map { AppKey(key: row["app_path"] ?? $0, name: row["app_name"] ?? $0) }
                return EventMark(ts: row["ts"], kind: row["kind"], severity: row["severity"], message: row["message"], app: app)
            }
        }
    }
}
