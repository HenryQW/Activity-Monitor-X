// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Foundation
import GRDB

public struct RetentionPolicy: Sendable {
    public var raw: TimeInterval = 86_400
    public var minute: TimeInterval = 2_592_000
    public var hour: TimeInterval = 31_536_000
    public var maxBytes: Int64 = 2_000_000_000
    public init() {}
}

/// Periodic maintenance. Each step commits its own short transaction so the sample
/// writer never waits long; watermarks in `meta` make every step safe to repeat.
public enum Rollup {
    private struct Tier { let table: String, time: String, key: String }
    private static let batch = 10_000
    /// Finest first: the size cap deletes in this order.
    private static let tiers = [
        Tier(table: "process_samples", time: "ts", key: "process_id, ts"),
        Tier(table: "system_samples", time: "ts", key: "rowid"),
        Tier(table: "process_minute", time: "bucket", key: "rowid"),
        Tier(table: "system_minute", time: "bucket", key: "rowid"),
        Tier(table: "process_hour", time: "bucket", key: "rowid"),
        Tier(table: "system_hour", time: "bucket", key: "rowid"),
    ]
    private static let events = Tier(table: "events", time: "ts", key: "rowid")

    public static func run(db: DatabaseQueue, now: Double, policy: RetentionPolicy) throws {
        try db.write { try rollRawToMinute($0, now: now) }
        try db.write { try rollMinuteToHour($0) }
        let windows = [policy.raw, policy.raw, policy.minute, policy.minute, policy.hour, policy.hour, policy.hour]
        for (tier, window) in zip(tiers + [events], windows) {
            while try db.write({ try deleteOldest($0, tier, before: now - window) }) == batch {}
        }
        try db.write { try pruneIfDue($0, now: now, cutoff: now - policy.hour) }
        try db.write { try $0.execute(sql: "PRAGMA incremental_vacuum(2000)") }
        try enforceSizeCap(db, maxBytes: policy.maxBytes)
    }

    // A raw row holds [ts, next) (carry-forward). A gap over 65 s (60 s heartbeat plus jitter)
    // means the process ended or the Mac slept, so the row then holds one tick, [ts, ts + 5).
    // A hold is at most 65 s, so it touches at most 3 buckets; each bucket gets its share.
    // A bucket is complete only 65 s after its end, when its last row can see its next row.
    // LEAD reads from 65 s before `from` so the first bucket gets the hold carried into it.
    private static func rollRawToMinute(_ db: Database, now: Double) throws {
        let from = try meta(db, "minute_watermark"), to = ((now - 65) / 60).rounded(.down) * 60
        guard to > from else { return }
        let m = Schema.procMetrics
        let cols = m.flatMap { ["\($0)_avg", "\($0)_max"] }
        try db.execute(literal: """
            INSERT INTO process_minute(process_id, bucket, samples, \(sql: cols.joined(separator: ", ")))
            SELECT process_id, bucket, MAX(1, CAST(ROUND(SUM(dt)) AS INTEGER)),
                   \(sql: m.map { "SUM(\($0) * dt) / SUM(IIF(\($0) IS NULL, 0, dt)), MAX(\($0))" }.joined(separator: ", "))
            FROM (SELECT *, MIN(stop, bucket + 60) - MAX(ts, bucket) AS dt
                  FROM (SELECT r.*, r.b + 60 * k.column1 AS bucket, IIF(r.next - r.ts <= 65, r.next, r.ts + 5) AS stop
                        FROM (SELECT *, CAST(ts / 60 AS INTEGER) * 60 AS b,
                                     LEAD(ts) OVER (PARTITION BY process_id ORDER BY ts) AS next
                              FROM process_samples INDEXED BY idx_process_samples_ts WHERE ts >= \(from - 65)) AS r,
                             (VALUES (0), (1), (2)) AS k)
                  WHERE bucket >= \(from) AND bucket < \(to))
            WHERE dt > 0
            GROUP BY process_id, bucket
            ON CONFLICT(process_id, bucket) DO UPDATE SET \(sql: upsertSet(["samples"] + cols))
            """)

        let s = Schema.sysMetrics
        let sysCols = s.flatMap { Schema.maxOnly.contains($0) ? ["\($0)_max"] : ["\($0)_avg", "\($0)_max"] }
        let sysAggs = s.map { Schema.maxOnly.contains($0) ? "MAX(\($0))" : "AVG(\($0)), MAX(\($0))" }
        try db.execute(literal: """
            INSERT INTO system_minute(bucket, samples, \(sql: sysCols.joined(separator: ", ")))
            SELECT CAST(ts / 60 AS INTEGER) * 60 AS b, COUNT(*), \(sql: sysAggs.joined(separator: ", "))
            FROM system_samples WHERE ts >= \(from) AND ts < \(to)
            GROUP BY b
            ON CONFLICT(bucket) DO UPDATE SET \(sql: upsertSet(["samples"] + sysCols))
            """)
        try setMeta(db, "minute_watermark", to)
    }

    private static func rollMinuteToHour(_ db: Database) throws {
        // An hour is complete only when all its minutes are rolled.
        let from = try meta(db, "hour_watermark")
        let to = (try meta(db, "minute_watermark") / 3600).rounded(.down) * 3600
        guard to > from else { return }
        let procCols = Schema.procMetrics.flatMap { ["\($0)_avg", "\($0)_max"] }
        let sysCols = Schema.sysMetrics.flatMap { Schema.maxOnly.contains($0) ? ["\($0)_max"] : ["\($0)_avg", "\($0)_max"] }
        // A NULL average carries no weight, so it must not dilute the others.
        let aggs = { (cols: [String]) in
            cols.map {
                $0.hasSuffix("_max") ? "MAX(\($0))" : "SUM(\($0) * samples) / SUM(IIF(\($0) IS NULL, 0, samples))"
            }.joined(separator: ", ")
        }
        for (table, key, cols) in [("process", "process_id, ", procCols), ("system", "", sysCols)] {
            try db.execute(literal: """
                INSERT INTO \(sql: table)_hour(\(sql: key)bucket, samples, \(sql: cols.joined(separator: ", ")))
                SELECT \(sql: key)CAST(bucket / 3600 AS INTEGER) * 3600 AS hb, SUM(samples), \(sql: aggs(cols))
                FROM \(sql: table)_minute WHERE bucket >= \(from) AND bucket < \(to)
                GROUP BY \(sql: key)hb
                ON CONFLICT(\(sql: key)bucket) DO UPDATE SET \(sql: upsertSet(["samples"] + cols))
                """)
        }
        try setMeta(db, "hour_watermark", to)
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
        for table in ["process_samples", "process_minute", "process_hour"] {
            stale = stale.filter(!Table(table).filter(Column("process_id") == p[Column("id")]).exists())
        }
        try stale.deleteAll(db)
        try setMeta(db, "prune_at", now)
    }

    private static func enforceSizeCap(_ db: DatabaseQueue, maxBytes: Int64) throws {
        for _ in 0..<50 {
            let done = try db.write { db -> Bool in
                let used = try Int64.fetchOne(db, sql: """
                    SELECT (page_count - freelist_count) * page_size
                    FROM pragma_page_count, pragma_freelist_count, pragma_page_size
                    """)!
                guard used > maxBytes,
                      try tiers.contains(where: { try deleteOldest(db, $0, before: .infinity) > 0 })
                else { return true }
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
