import Foundation
import GRDB
import Testing
@testable import AMXCore

/// Aligned to both 60 s and 3600 s.
private let b = 1_800_000_000.0

private struct Rig {
    let db: DatabaseQueue
    let pid: Int64
    init() throws {
        db = try Store.openWriter(path: NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite")
        pid = try Self.insertProcess(db, lastSeen: 3e9)
    }
    func addProcess(lastSeen: Double) throws -> Int64 { try Self.insertProcess(db, lastSeen: lastSeen) }
    static func insertProcess(_ db: DatabaseQueue, lastSeen: Double) throws -> Int64 {
        try db.write { db in
            let next = try Int32.fetchOne(db, sql: "SELECT IFNULL(MAX(pid), 0) + 1 FROM processes")!
            let p = ProcessRecord(id: nil, pid: next, startTime: 0, name: "p", path: nil,
                                  appPath: nil, appName: nil, bundleId: nil, teamId: nil, uid: 0, translated: false,
                                  firstSeen: 0, lastSeen: lastSeen)
            try p.insert(db)
            return db.lastInsertedRowID
        }
    }
    func raw(_ ts: Double, cpu: Double, netIn: Double = 0) throws {
        try db.write {
            try ProcessSampleRecord(processId: pid, ts: ts, cpu: cpu, mem: 0, diskR: 0, diskW: 0, energy: 0, gpu: 0,
                                    netIn: netIn, netOut: 0).insert($0)
        }
    }
    func buckets(_ table: String) throws -> [Double] {
        try db.read { try Double.fetchAll($0, sql: "SELECT bucket FROM \(table) ORDER BY bucket") }
    }
    func exec(_ sql: String) throws { try db.write { try $0.execute(sql: sql) } }
    func row(_ sql: String) throws -> Row? { try db.read { try Row.fetchOne($0, sql: sql) } }
    func count(_ table: String) throws -> Int { try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! } }
    func run(_ now: Double, _ policy: RetentionPolicy = RetentionPolicy()) throws {
        try Rollup.run(db: db, now: now, policy: policy)
    }
}

@Suite struct RollupTests {
    @Test func dtWeightedMinuteAverage() throws {
        let r = try Rig()
        try r.raw(b, cpu: 10)
        try r.raw(b + 5, cpu: 100)
        try r.raw(b + 60, cpu: 0)
        try r.exec("INSERT INTO system_samples(ts, cpu, pressure_level) VALUES (\(b), 10, 1), (\(b + 5), 30, 2)")
        // Bucket b is complete once now - 65 >= b + 60.
        try r.run(b + 125)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        // Hold segments: 10 holds [b, b+5), 100 holds [b+5, b+60).
        #expect(abs((p["cpu_avg"] as Double) - 92.5) < 1e-9)
        #expect(p["cpu_max"] as Double == 100 && p["samples"] as Int == 60)
        let s = try #require(try r.row("SELECT * FROM system_minute WHERE bucket = \(b)"))
        #expect(s["cpu_avg"] as Double == 20 && s["cpu_max"] as Double == 30)
        #expect(s["pressure_level_max"] as Double == 2 && s["samples"] as Int == 2)
    }

    @Test func gapUsesOneTick() throws {
        let r = try Rig()
        try r.raw(b, cpu: 100)
        try r.raw(b + 8 * 3600, cpu: 0)
        try r.run(b + 8 * 3600 + 120)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        #expect(p["cpu_avg"] as Double == 100 && p["samples"] as Int == 5)
    }

    @Test func sparseRowsCarryForward() throws {
        let r = try Rig()
        try r.raw(b, cpu: 0.3)
        try r.raw(b + 50, cpu: 50)
        try r.raw(b + 110, cpu: 50)
        // Only bucket b is complete; its last row still sees the next row at b + 110.
        try r.run(b + 125)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        #expect(abs((p["cpu_avg"] as Double) - (0.3 * 50 + 50 * 10) / 60) < 1e-9)
        #expect(p["samples"] as Int == 60)
        #expect(try r.count("process_minute") == 1)
    }

    @Test func rollupBeforeNextRowThenAfter() throws {
        let r = try Rig()
        try r.raw(b + 20, cpu: 10)
        // The next row may still come at b + 80: bucket b must wait.
        try r.run(b + 70)
        #expect(try r.count("process_minute") == 0)
        try r.raw(b + 80, cpu: 10)
        try r.run(b + 60 + 65 + 60)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        #expect(p["cpu_avg"] as Double == 10 && p["samples"] as Int == 40)
    }

    @Test func carryInSegment() throws {
        let r = try Rig()
        try r.raw(b - 5, cpu: 0)
        try r.run(b + 65)
        // Bucket b - 60 is rolled; bucket b starts after the watermark, but row b - 5 still holds into it.
        try r.raw(b + 50, cpu: 100)
        try r.raw(b + 110, cpu: 100)
        try r.run(b + 125)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        #expect(abs((p["cpu_avg"] as Double) - (0.0 * 50 + 100 * 10) / 60) < 1e-9)
        #expect(p["cpu_max"] as Double == 100 && p["samples"] as Int == 60)
    }

    @Test func holdSpansThreeBuckets() throws {
        let r = try Rig()
        try r.raw(b, cpu: 0)
        try r.raw(b + 59, cpu: 10)
        try r.raw(b + 124, cpu: 30)
        try r.run(b + 180 + 65)
        // [b+59, b+124) gives 1 s, 60 s, 4 s; the row at b+124 adds one tick to bucket b+120.
        let rows = try r.db.read { try Row.fetchAll($0, sql: "SELECT samples, cpu_avg FROM process_minute ORDER BY bucket") }
        #expect(rows.map { $0["samples"] as Int } == [60, 60, 9])
        #expect(rows.map { $0["cpu_avg"] as Double } == [10.0 / 60, 10, 190.0 / 9])
    }

    @Test func nullMetricDoesNotDilute() throws {
        let r = try Rig()
        try r.exec("""
            INSERT INTO process_samples(process_id, ts, cpu, gpu)
              VALUES (\(r.pid), \(b), 1, NULL), (\(r.pid), \(b + 30), 1, 50), (\(r.pid), \(b + 60), 1, 50)
            """)
        try r.run(b + 125)
        let p = try #require(try r.row("SELECT * FROM process_minute WHERE bucket = \(b)"))
        #expect(p["gpu_avg"] as Double == 50 && p["samples"] as Int == 60)
    }

    @Test func retentionDefaults() {
        let p = RetentionPolicy()
        #expect(p.raw == 86_400 && p.minute == 2_592_000 && p.hour == 7_776_000)
    }

    /// Rows every 60 s: each one holds one full minute bucket, so a bucket's average is that row's value.
    @Test func minuteTierIsSparse() throws {
        let r = try Rig()
        // 10.4 is within 0.5 of the last written 10; 10.8 is not (it would be within 0.5 of 10.4).
        let cpu = [10, 10.4, 10.8, 10.8] + Array(repeating: 10.8, count: 63)
        for (i, v) in cpu.enumerated() { try r.raw(b + Double(i) * 60, cpu: v, netIn: i == 4 ? 1 : 0) }
        try r.run(b + 66 * 60 + 65)
        // 0: first row; 2: cpu moved 0.8; 4 and 5: net_in_max crossed zero; 65: 60 min heartbeat after 5.
        #expect(try r.buckets("process_minute") == [0, 2, 4, 5, 65].map { b + Double($0) * 60 })
    }

    @Test func hourTierFromRawAndSparse() throws {
        let r = try Rig()
        for i in 0...120 { try r.raw(b + Double(i) * 60, cpu: 10) }
        try r.run(b + 7200 + 65)
        // The minute tier holds one row for both hours, so the hour must come from raw rows.
        #expect(try r.buckets("process_minute") == [b, b + 3600])
        let h = try r.db.read { try Row.fetchAll($0, sql: "SELECT * FROM process_hour") }
        // Hour b + 3600 equals hour b, so it is not written.
        #expect(h.count == 1)
        #expect(h.first?["bucket"] as Double? == b && h.first?["samples"] as Int? == 3600)
        #expect(h.first?["cpu_avg"] as Double? == 10 && h.first?["cpu_max"] as Double? == 10)
    }

    @Test func systemTiersAreDense() throws {
        let r = try Rig()
        try r.exec("""
            INSERT INTO system_samples(ts, cpu, thermal_state)
              VALUES (\(b), 10, 1), (\(b + 60), 40, 3), (\(b + 120), 40, 3), (\(b + 3600), 40, 3)
            """)
        // The hour rolls only once the minute watermark reaches b + 3600.
        try r.run(b + 3610)
        #expect(try r.count("system_hour") == 0)
        try r.run(b + 3665)
        #expect(try r.buckets("system_minute") == [b, b + 60, b + 120])
        let s = try #require(try r.row("SELECT * FROM system_hour WHERE bucket = \(b)"))
        #expect(s["cpu_avg"] as Double == 30 && s["cpu_max"] as Double == 40 && s["samples"] as Int == 3)
        #expect(s["thermal_state_max"] as Double == 3)
    }

    @Test func rollsDiskFree() throws {
        let r = try Rig()
        try r.exec("INSERT INTO system_samples(ts, disk_free) VALUES (\(b), 100), (\(b + 5), 300)")
        try r.run(b + 125)
        let s = try #require(try r.row("SELECT * FROM system_minute WHERE bucket = \(b)"))
        #expect(s["disk_free_avg"] as Double == 200 && s["disk_free_max"] as Double == 300)
    }

    @Test func rollupIsIdempotent() throws {
        let r = try Rig()
        for (i, cpu) in [5.0, 50, 20, 80].enumerated() { try r.raw(b + Double(i) * 17, cpu: cpu) }
        try r.exec("INSERT INTO system_samples(ts, cpu) VALUES (\(b), 10), (\(b + 70), 30)")
        let snapshot = {
            try r.db.read { db in
                try ["process_minute", "process_hour", "system_minute", "system_hour"].map {
                    try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY 1, 2")
                }
            }
        }
        try r.run(b + 3700)
        let first = try snapshot()
        #expect(first.allSatisfy { !$0.isEmpty })
        try r.run(b + 3700)
        #expect(try snapshot() == first)
        // Rewinding the watermarks re-rolls the same buckets; the upsert overwrites stale values.
        try r.exec("DELETE FROM meta; UPDATE process_minute SET cpu_avg = -1; UPDATE system_hour SET cpu_avg = -1")
        try r.run(b + 3700)
        #expect(try snapshot() == first)
    }

    @Test func trimRespectsWindows() throws {
        let r = try Rig()
        let now = 2_000_000_030.0
        let p = RetentionPolicy()
        let cases: [(table: String, column: String, window: Double, extra: String, values: String)] = [
            ("process_samples", "ts", p.raw, "process_id, ", "\(r.pid), "),
            ("system_samples", "ts", p.raw, "", ""),
            ("process_minute", "bucket", p.minute, "process_id, samples, ", "\(r.pid), 1, "),
            ("system_minute", "bucket", p.minute, "samples, ", "1, "),
            ("process_hour", "bucket", p.hour, "process_id, samples, ", "\(r.pid), 1, "),
            ("system_hour", "bucket", p.hour, "samples, ", "1, "),
            ("events", "ts", p.hour, "kind, severity, message, ", "'k', 1, 'm', "),
        ]
        for c in cases {
            for t in [now - c.window - 1, now - c.window + 1] {
                try r.exec("INSERT INTO \(c.table)(\(c.extra)\(c.column)) VALUES (\(c.values)\(t))")
            }
        }
        try r.run(now)
        for c in cases {
            let kept = try r.db.read {
                try Double.fetchAll($0, sql: "SELECT \(c.column) FROM \(c.table) WHERE \(c.column) IN (?, ?)",
                                    arguments: [now - c.window - 1, now - c.window + 1])
            }
            #expect(kept == [now - c.window + 1], "\(c.table)")
        }
    }

    @Test func pruneDropsStaleProcessesWithoutRows() throws {
        let r = try Rig()
        let now = 2_000_000_030.0
        let stale = now - RetentionPolicy().hour - 1
        let gone = try r.addProcess(lastSeen: stale)
        let kept = try r.addProcess(lastSeen: stale)
        // Its last row, in its last minute, is still within the hour tier's window.
        try r.exec("INSERT INTO process_hour(process_id, bucket, samples) VALUES (\(kept), \(stale + 1), 1)")
        try r.run(now)
        let ids = try r.db.read { try Int64.fetchSet($0, sql: "SELECT id FROM processes") }
        #expect(!ids.contains(gone) && ids.contains(kept))
        // Pruning runs at most every 600 s.
        let later = try r.addProcess(lastSeen: stale)
        try r.run(now + 599)
        #expect(try r.db.read { try ProcessRecord.exists($0, key: later) })
    }

    @Test func vacuumKeepsReusablePagesFree() throws {
        let r = try Rig()
        func free(after pages: Int) throws -> Int {
            try r.exec("""
                CREATE TABLE junk(x);
                WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < \(pages))
                INSERT INTO junk SELECT randomblob(3000) FROM n;
                DROP TABLE junk;
                """)
            try r.run(b)
            return try r.db.read { try Int.fetchOne($0, sql: "PRAGMA freelist_count")! }
        }
        #expect(try free(after: 100) > 90)
        #expect(try free(after: 3000) == Rollup.reusable)
    }

    @Test func trimKeepsRawTheHourNeeds() throws {
        let r = try Rig()
        for i in 0..<30 { try r.raw(b + Double(i) * 60, cpu: Double(i)) }
        var policy = RetentionPolicy()
        policy.raw = 60
        // Minutes up to b + 1800 are rolled, but hour b is not: its raw rows must stay.
        try r.run(b + 1800 + 65, policy)
        #expect(try r.count("process_minute") == 30)
        #expect(try r.count("process_samples") == 30)
    }

    @Test func sizeCapKeepsUnrolledRaw() throws {
        let r = try Rig()
        let minute = 2_000_000_040.0
        for i in 0..<50 {
            try r.exec("INSERT INTO process_hour(process_id, bucket, samples) VALUES (\(r.pid), \(minute - Double(i) * 3600), 60)")
        }
        // 15_000 rows in the current, incomplete minute: no tier has them yet.
        try r.db.write { db in
            for i in 0..<15_000 {
                try ProcessSampleRecord(processId: r.pid, ts: minute + Double(i) * 0.003, cpu: 1, mem: 0, diskR: 0,
                                        diskW: 0, energy: 0, gpu: 0, netIn: 0, netOut: 0).insert(db)
            }
        }
        let used = "SELECT (SELECT page_count FROM pragma_page_count) - (SELECT freelist_count FROM pragma_freelist_count)"
        let pageSize = try r.db.read { try Int64.fetchOne($0, sql: "PRAGMA page_size")! }
        let baseline = try r.db.read { try Int64.fetchOne($0, sql: used)! } * pageSize
        for i in 1...15_000 {
            try r.exec("INSERT INTO process_minute(process_id, bucket, samples) VALUES (\(r.pid), \(minute - Double(i) * 60), 60)")
        }
        var policy = RetentionPolicy()
        policy.maxBytes = baseline + 4 * pageSize
        #expect(try r.db.read { try Int64.fetchOne($0, sql: used)! } * pageSize > policy.maxBytes)
        try r.run(minute + 50, policy)
        // Minute rows go before hour rows; the raw rows are never deleted.
        #expect(try r.count("process_minute") == 0)
        #expect(try r.count("process_hour") == 50)
        #expect(try r.count("process_samples") == 15_000)
        policy.maxBytes = 1
        try r.run(minute + 55, policy)
        #expect(try r.count("process_hour") == 0)
        #expect(try r.count("process_samples") == 15_000)
    }
}
