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
    func raw(_ ts: Double, cpu: Double) throws {
        try db.write {
            try ProcessSampleRecord(processId: pid, ts: ts, cpu: cpu, mem: 0, diskR: 0, diskW: 0, energy: 0, gpu: 0,
                                    netIn: 0, netOut: 0).insert($0)
        }
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
        try r.raw(b + 59, cpu: 10)
        try r.raw(b + 124, cpu: 10)
        try r.run(b + 180 + 65)
        // [b+59, b+124) gives 1 s, 60 s, 4 s; the row at b+124 adds one tick to bucket b+120.
        let samples = try r.db.read { try Int.fetchAll($0, sql: "SELECT samples FROM process_minute ORDER BY bucket") }
        #expect(samples == [1, 60, 9])
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

    @Test func hourRollupWeightsBySamples() throws {
        let r = try Rig()
        try r.exec("""
            INSERT INTO process_minute(process_id, bucket, samples, cpu_avg, cpu_max)
              VALUES (\(r.pid), \(b), 60, 10, 15), (\(r.pid), \(b + 60), 30, 40, 50);
            INSERT INTO system_minute(bucket, samples, cpu_avg, cpu_max, thermal_state_max)
              VALUES (\(b), 60, 10, 15, 1), (\(b + 60), 30, 40, 50, 3);
            """)
        // The hour rolls only once the minute watermark reaches b + 3600.
        try r.run(b + 3610)
        #expect(try r.count("process_hour") == 0)
        try r.run(b + 3665)
        let p = try #require(try r.row("SELECT * FROM process_hour WHERE bucket = \(b)"))
        #expect(p["cpu_avg"] as Double == 20 && p["cpu_max"] as Double == 50 && p["samples"] as Int == 90)
        let s = try #require(try r.row("SELECT * FROM system_hour WHERE bucket = \(b)"))
        #expect(s["cpu_avg"] as Double == 20 && s["cpu_max"] as Double == 50 && s["samples"] as Int == 90)
        #expect(s["thermal_state_max"] as Double == 3)
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
        try r.exec("INSERT INTO process_hour(process_id, bucket, samples) VALUES (\(kept), \(now - 3600), 1)")
        try r.run(now)
        let ids = try r.db.read { try Int64.fetchSet($0, sql: "SELECT id FROM processes") }
        #expect(!ids.contains(gone) && ids.contains(kept))
        // Pruning runs at most every 600 s.
        let later = try r.addProcess(lastSeen: stale)
        try r.run(now + 599)
        #expect(try r.db.read { try ProcessRecord.exists($0, key: later) })
    }

    @Test func sizeCapDropsFinestFirst() throws {
        let r = try Rig()
        let minute = 2_000_000_040.0
        for i in 0..<50 {
            try r.exec("INSERT INTO process_hour(process_id, bucket, samples) VALUES (\(r.pid), \(minute - Double(i) * 3600), 60)")
        }
        let used = "SELECT (SELECT page_count FROM pragma_page_count) - (SELECT freelist_count FROM pragma_freelist_count)"
        let pageSize = try r.db.read { try Int64.fetchOne($0, sql: "PRAGMA page_size")! }
        let baseline = try r.db.read { try Int64.fetchOne($0, sql: used)! } * pageSize
        // 15_000 rows in the current, incomplete minute: two delete batches, nothing rolls up.
        try r.db.write { db in
            for i in 0..<15_000 {
                try ProcessSampleRecord(processId: r.pid, ts: minute + Double(i) * 0.003, cpu: 1, mem: 0, diskR: 0,
                                        diskW: 0, energy: 0, gpu: 0, netIn: 0, netOut: 0).insert(db)
            }
        }
        var policy = RetentionPolicy()
        policy.maxBytes = baseline + 4 * pageSize
        #expect(try r.db.read { try Int64.fetchOne($0, sql: used)! } * pageSize > policy.maxBytes)
        try r.run(minute + 50, policy)
        #expect(try r.count("process_samples") == 0)
        #expect(try r.count("process_hour") == 50)
    }
}
