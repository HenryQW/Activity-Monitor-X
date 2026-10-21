// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Foundation
import GRDB
import os

public struct RetentionPolicy: Sendable {
    public var raw: TimeInterval = 86_400
    public var minute: TimeInterval = 2_592_000
    public var hour: TimeInterval = 7_776_000
    public var maxBytes: Int64 = 2_000_000_000
    public init() {}
}

/// Periodic maintenance. Each step commits its own short transaction so the sample
/// writer never waits long; watermarks in `meta` make every step safe to repeat.
public enum Rollup {
    private struct Tier {
        let table: String, time: String, key: String
        var isRaw: Bool { table.hasSuffix("_samples") }
    }
    private static let batch = 10_000
    /// Finest first: the size cap deletes in this order.
    private static let tiers = [
        Tier(table: "process_samples", time: "ts", key: "ts, process_id"),
        Tier(table: "system_samples", time: "ts", key: "rowid"),
        Tier(table: "process_minute", time: "bucket", key: "bucket, process_id"),
        Tier(table: "system_minute", time: "bucket", key: "rowid"),
        Tier(table: "process_hour", time: "bucket", key: "bucket, process_id"),
        Tier(table: "system_hour", time: "bucket", key: "rowid"),
    ]
    private static let events = Tier(table: "events", time: "ts", key: "rowid")
    private static let log = Logger(subsystem: AMX.daemonLabel, category: "rollup")

    public static func run(db: DatabaseQueue, now: Double, policy: RetentionPolicy) throws {
        try db.write { try roll($0, minute, to: ((now - 65) / 60).rounded(.down) * 60) }
        // An hour is complete only when all its minutes are.
        try db.write { try roll($0, hour, to: (try meta($0, "minute_watermark") / 3600).rounded(.down) * 3600) }
        // Raw rows from 65 s before the oldest unrolled bucket still feed a tier: never delete them.
        let rawBound = try db.read { try min(meta($0, "minute_watermark"), meta($0, "hour_watermark")) } - 65
        let windows = [policy.raw, policy.raw, policy.minute, policy.minute, policy.hour, policy.hour, policy.hour]
        for (tier, window) in zip(tiers + [events], windows) {
            let cutoff = tier.isRaw ? min(now - window, rawBound) : now - window
            while try db.write({ try deleteOldest($0, tier, before: cutoff) }) == batch {}
        }
        try db.write { try pruneIfDue($0, now: now, cutoff: now - policy.hour) }
        // Retention frees about as many pages as the next ticks need. Vacuuming those would move the pages the
        // ticks appended into the holes, then append again: keep up to `reusable` free for the inserts.
        try db.write { db in
            let excess = try Int.fetchOne(db, sql: "PRAGMA freelist_count")! - reusable
            if excess > 0 { try db.execute(sql: "PRAGMA incremental_vacuum(\(min(excess, 2000)))") }
        }
        try enforceSizeCap(db, maxBytes: policy.maxBytes, rawBound: rawBound)
    }

    /// Free pages kept for reuse: 8 MB, about an hour of inserts.
    static let reusable = 2048

    private struct Level { let name: String, width: Double, heartbeat: Double }
    private static let minute = Level(name: "minute", width: 60, heartbeat: 3600)
    private static let hour = Level(name: "hour", width: 3600, heartbeat: 86_400)
    /// The raw write gate, applied to a bucket against the process's last written bucket.
    private static let gate: [(column: String, threshold: Double, zero: Bool)] = [
        ("cpu_avg", 0.5, false), ("gpu_avg", 0.5, false), ("mem_avg", 524_288, false),
        ("cpu_max", 0.5, false), ("gpu_max", 0.5, false), ("disk_r_max", 1024, true), ("disk_w_max", 1024, true),
        ("net_in_max", 1024, true), ("net_out_max", 1024, true),
    ]

    private static func roll(_ db: Database, _ level: Level, to: Double) throws {
        let key = "\(level.name)_watermark", from = try meta(db, key)
        guard to > from else { return }
        try rollProcesses(db, level, from: from, to: to)
        try rollSystem(db, level, from: from, to: to)
        try setMeta(db, key, to)
    }

    // A raw row holds [ts, next) (carry-forward). A gap over 65 s (60 s heartbeat plus jitter)
    // means the process ended or the Mac slept, so the row then holds one tick, [ts, ts + 5).
    // A hold is at most 65 s, so it touches at most 3 buckets; each bucket gets its share.
    // A minute is complete only 65 s after its end, when its last row can see its next row.
    // LEAD reads from 65 s before the bucket so the bucket gets the hold carried into it, and up to
    // 65 s after it, which covers the next row of every hold that reaches the bucket.
    //
    // Tiers are sparse: a bucket is written only when it passes the raw gate against the process's
    // last written bucket in the same tier, or that bucket is a heartbeat old. A missing bucket means
    // the process's last written row still holds, until `processes.last_seen`. Buckets roll in order,
    // one statement each, so each compares against the rows written before it. A last row older than
    // the heartbeat passes the gate anyway, so only rows within the heartbeat are looked up.
    private static func rollProcesses(_ db: Database, _ level: Level, from: Double, to: Double) throws {
        let w = level.width
        guard let first = try ProcessSampleRecord.filter(Column("ts") >= from - 65)
            .select(min(Column("ts")), as: Double.self).fetchOne(db)
        else { return }
        let m = Schema.procMetrics
        let cols = m.flatMap { ["\($0)_avg", "\($0)_max"] }
        let changed = gate.map { g -> String in
            let c = g.column
            return "(a.\(c) IS NULL) != (p.\(c) IS NULL) OR ABS(a.\(c) - p.\(c)) > \(g.threshold)"
                + (g.zero ? " OR (a.\(c) = 0) != (p.\(c) = 0)" : "")
        }.joined(separator: " OR ")
        var bucket = max(from, (first / w).rounded(.down) * w)
        while bucket < to {
            try db.execute(literal: """
                WITH a AS (
                  SELECT process_id, bucket, MAX(1, CAST(ROUND(SUM(dt)) AS INTEGER)) AS samples,
                         \(sql: m.map { "SUM(\($0) * dt) / SUM(IIF(\($0) IS NULL, 0, dt)) AS \($0)_avg, MAX(\($0)) AS \($0)_max" }.joined(separator: ", "))
                  FROM (SELECT *, MIN(stop, bucket + \(w)) - MAX(ts, bucket) AS dt
                        FROM (SELECT r.*, r.b + \(w) * k.column1 AS bucket, IIF(r.next - r.ts <= 65, r.next, r.ts + 5) AS stop
                              FROM (SELECT *, CAST(ts / \(w) AS INTEGER) * \(w) AS b,
                                           LEAD(ts) OVER (PARTITION BY process_id ORDER BY ts) AS next
                                    FROM process_samples
                                    WHERE ts >= \(bucket - 65) AND ts < \(bucket + w + 65)) AS r,
                                   (VALUES (0), (1), (2)) AS k)
                        WHERE bucket = \(bucket))
                  WHERE dt > 0
                  GROUP BY process_id),
                prev AS (
                  SELECT process_id, MAX(bucket) AS bucket FROM process_\(sql: level.name)
                  WHERE bucket >= \(bucket - level.heartbeat) AND bucket < \(bucket)
                  GROUP BY process_id)
                INSERT INTO process_\(sql: level.name)(bucket, process_id, samples, \(sql: cols.joined(separator: ", ")))
                SELECT a.bucket, a.process_id, a.samples, \(sql: cols.map { "a.\($0)" }.joined(separator: ", "))
                FROM a LEFT JOIN prev l ON l.process_id = a.process_id
                LEFT JOIN process_\(sql: level.name) p ON p.bucket = l.bucket AND p.process_id = a.process_id
                WHERE p.process_id IS NULL OR a.bucket - p.bucket >= \(level.heartbeat) OR \(sql: changed)
                ON CONFLICT(bucket, process_id) DO UPDATE SET \(sql: upsertSet(["samples"] + cols))
                """)
            bucket += w
        }
    }

    /// System rows are dense: one per bucket with samples, straight from the raw tier.
    private static func rollSystem(_ db: Database, _ level: Level, from: Double, to: Double) throws {
        let s = Schema.sysMetrics
        let cols = s.flatMap { Schema.maxOnly.contains($0) ? ["\($0)_max"] : ["\($0)_avg", "\($0)_max"] }
        let aggs = s.map { Schema.maxOnly.contains($0) ? "MAX(\($0))" : "AVG(\($0)), MAX(\($0))" }
        try db.execute(literal: """
            INSERT INTO system_\(sql: level.name)(bucket, samples, \(sql: cols.joined(separator: ", ")))
            SELECT CAST(ts / \(level.width) AS INTEGER) * \(level.width) AS b, COUNT(*), \(sql: aggs.joined(separator: ", "))
            FROM system_samples WHERE ts >= \(from) AND ts < \(to)
            GROUP BY b
            ON CONFLICT(bucket) DO UPDATE SET \(sql: upsertSet(["samples"] + cols))
            """)
    }

    private static func upsertSet(_ cols: [String]) -> String {
        cols.map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
    }

    /// Deletes up to `batch` of the oldest rows older than `cutoff`; returns the count.
    private static func deleteOldest(_ db: Database, _ t: Tier, before cutoff: Double) throws -> Int {
        try db.execute(literal: """
            DELETE FROM \(sql: t.table) WHERE (\(sql: t.key)) IN (
              SELECT \(sql: t.key) FROM \(sql: t.table) WHERE \(sql: t.time) < \(cutoff)
              ORDER BY \(sql: t.time) LIMIT \(batch))
            """)
        return db.changesCount
    }

    private static func pruneIfDue(_ db: Database, now: Double, cutoff: Double) throws {
        let last = try meta(db, "prune_at")
        // `now < last`: the clock went back; prune now rather than wait for it to catch up.
        guard now - last >= 600 || now < last else { return }
        let p = TableAlias()
        var stale = ProcessRecord.aliased(p).filter(Column("last_seen") < cutoff)
        // A process's rows end within 65 s after its `last_seen`. No index starts with process_id, so the
        // time bound keeps each lookup to the few rows between the oldest kept row and that end.
        for t in tiers where t.table.hasPrefix("process_") {
            stale = stale.filter(!Table(t.table).filter(
                Column(t.time) < p[Column("last_seen")] + 120 && Column("process_id") == p[Column("id")]).exists())
        }
        try stale.deleteAll(db)
        try setMeta(db, "prune_at", now)
    }

    private static func enforceSizeCap(_ db: DatabaseQueue, maxBytes: Int64, rawBound: Double) throws {
        for _ in 0..<50 {
            let done = try db.write { db -> Bool in
                let used = try Int64.fetchOne(db, sql: """
                    SELECT (page_count - freelist_count) * page_size
                    FROM pragma_page_count, pragma_freelist_count, pragma_page_size
                    """)!
                guard used > maxBytes else { return true }
                guard try tiers.contains(where: { try deleteOldest(db, $0, before: $0.isRaw ? rawBound : .infinity) > 0 })
                else {
                    log.error("size cap \(maxBytes, privacy: .public) B not met: \(used, privacy: .public) B in use, only unrolled raw rows left")
                    return true
                }
                try db.execute(sql: "PRAGMA incremental_vacuum(2000)")
                return false
            }
            if done { return }
        }
    }

    private static func meta(_ db: Database, _ key: String) throws -> Double {
        try MetaRecord.fetchOne(db, key: key)?.value ?? 0
    }

    private static func setMeta(_ db: Database, _ key: String, _ value: Double) throws {
        try MetaRecord(key: key, value: value).upsert(db)
    }
}
