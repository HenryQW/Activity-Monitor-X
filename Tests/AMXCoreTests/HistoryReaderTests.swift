import Foundation
import GRDB
import Testing
@testable import AMXCore

private struct Rig {
    let db: DatabaseQueue
    let pool: DatabasePool
    let pid: Int64
    init(lastSeen: Double, firstSeen: Double = 0, bundleId: String? = nil, teamId: String? = nil) throws {
        let path = NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
        db = try Store.openWriter(path: path)
        pool = try Store.openReader(path: path)
        pid = try db.write { db in
            let p = ProcessRecord(id: nil, pid: 1, startTime: 0, name: "p", path: nil, appPath: nil, appName: nil,
                                  bundleId: bundleId, teamId: teamId, uid: 0, translated: false, firstSeen: firstSeen, lastSeen: lastSeen)
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
    func tier(_ table: String, _ bucket: Double, cpu: Double = 0, mem: Double = 0, memMax: Double = 0) throws {
        try db.write {
            try $0.execute(sql: """
                INSERT INTO \(table)(process_id, bucket, samples, cpu_avg, cpu_max, mem_avg, mem_max)
                VALUES (?, ?, 1, ?, ?, ?, ?)
                """, arguments: [pid, bucket, cpu, cpu, mem, memMax])
        }
    }
    func tier(_ table: String, _ bucket: Double, diskR: Double, diskW: Double) throws {
        try db.write {
            try $0.execute(sql: """
                INSERT INTO \(table)(process_id, bucket, samples, disk_r_avg, disk_r_max, disk_w_avg, disk_w_max)
                VALUES (?, ?, 1, ?, ?, ?, ?)
                """, arguments: [pid, bucket, diskR, diskR, diskW, diskW])
        }
    }
    func tracks(_ range: HistoryRange, _ metric: Metric, end: Double, device: Device = .current) throws -> [ProcessTrack] {
        try HistoryReader(pool: pool, device: device).tracks(range: range, metric: metric, end: end)
    }
}

private func spans(_ t: ProcessTrack) -> [[Double]] { t.slices.map { [$0.start, $0.end, $0.value] } }

private let testDevice = Device(cores: 10, memory: 17_179_869_184)

@Suite struct HistoryReaderTests {
    @Test func scoreTracksFromTiers() throws {
        let r = try Rig(lastSeen: 3600)
        try r.tier("process_minute", 0, cpu: 100, mem: 4_294_967_296, memMax: 4_294_967_296)
        let minute = try #require(try r.tracks(.day, .score, end: 86_400, device: testDevice).first)
        #expect(minute.slices.first?.value == 17.5)
        let raw = try Rig(lastSeen: 59)
        try raw.raw(0, cpu: 50)
        #expect(try #require(try raw.tracks(.hour, .score, end: 60, device: testDevice).first).slices.first?.value == 2.5)
    }

    @Test func tracksCarryBundleAndTeam() throws {
        let r = try Rig(lastSeen: 59, bundleId: "com.x", teamId: "T1")
        try r.raw(0, cpu: 1)
        let t = try #require(try r.tracks(.hour, .cpu, end: 60).first)
        #expect(t.candidate == GroupCandidate(name: "p", path: nil, bundleID: "com.x", teamID: "T1"))
    }

    @Test func emptyDatabaseGivesNoTracks() throws {
        let r = try Rig(lastSeen: 0)
        #expect(try r.tracks(.day, .cpu, end: 86_400).isEmpty)
    }

    @Test func rawRowsHoldUntilNextRow() throws {
        let r = try Rig(lastSeen: 59)
        try r.raw(0, cpu: 10)
        try r.raw(30, cpu: 50)
        let t = try #require(try r.tracks(.hour, .cpu, end: 60).first)
        #expect(spans(t) == [[0, 30, 10], [30, 60, 50]])
    }

    @Test func tracksCarryLastSeen() throws {
        let r = try Rig(lastSeen: 100)
        try r.raw(0, cpu: 10)
        #expect(try r.tracks(.hour, .cpu, end: 200).first?.lastSeen == 100)
    }

    @Test func endedProcessStopsAtLastSeen() throws {
        let r = try Rig(lastSeen: 100)
        try r.tier("process_minute", 0, cpu: 20)
        try r.tier("process_minute", 60, cpu: 20)
        let t = try #require(try r.tracks(.day, .cpu, end: 3600).first)
        #expect(t.slices.last?.end == 160)
    }

    @Test func openProcessStopsAtWritersLastMinute() throws {
        let r = try Rig(lastSeen: .infinity)
        try r.tier("process_minute", 0, cpu: 20)
        // The writer's last ticks; it stopped at 125, in the minute that 121 opened.
        try r.db.write { try $0.execute(sql: "INSERT INTO system_samples(ts) VALUES (116), (121), (125)") }
        let t = try #require(try r.tracks(.day, .cpu, end: 3600).first)
        #expect(t.slices.last?.end == 181)
    }

    @Test func carryInFromBeforeRange() throws {
        let r = try Rig(lastSeen: 1e9)
        try r.tier("process_minute", -1800, cpu: 7)
        let t = try #require(try r.tracks(.day, .cpu, end: 86_400).first)
        #expect(spans(t) == [[0, 1860, 7]])
    }

    @Test func idleHeartbeatHolds() throws {
        let r = try Rig(lastSeen: 1e9)
        let end = 7 * 86_400.0
        for d in 0..<7 { try r.tier("process_hour", Double(d) * 86_400, cpu: 3) }
        let t = try #require(try r.tracks(.week, .cpu, end: end).first)
        // Each hour row holds 90 000 s, so consecutive slices abut with no gap.
        #expect(t.slices.count == 7)
        #expect(t.slices.first?.start == 0 && t.slices.last?.end == end)
        for (a, b) in zip(t.slices, t.slices.dropFirst()) { #expect(a.end == b.start) }
    }

    @Test func shortLivedProcessHoldsHourRowOnlyWhileAlive() throws {
        let b = 7200.0
        let r = try Rig(lastSeen: b + 1800, firstSeen: b + 1800)
        try r.tier("process_hour", b, cpu: 50)
        let t = try #require(try r.tracks(.week, .cpu, end: 7 * 86_400).first)
        #expect(spans(t) == [[b + 1800, b + 1860, 50]])
    }

    @Test func memoryUsesFootprintAvg() throws {
        let r = try Rig(lastSeen: 1e9)
        try r.tier("process_hour", 0, mem: 1e9, memMax: 2e9)
        let s = try #require(try r.tracks(.week, .memory, end: 3600).first?.slices.first)
        #expect(s.value == 1e9)
    }

    @Test func rawGapPastHeartbeatCoversOneTick() throws {
        let r = try Rig(lastSeen: 159)
        try r.raw(0, cpu: 1)
        try r.raw(100, cpu: 2)
        let t = try #require(try r.tracks(.hour, .cpu, end: 200).first)
        #expect(spans(t) == [[0, 5, 1], [100, 165, 2]])
    }

    @Test func lastRowCappedAtHold() throws {
        let r = try Rig(lastSeen: 1e9)
        try r.tier("process_minute", 0, cpu: 4)
        let t = try #require(try r.tracks(.day, .cpu, end: 86_400).first)
        #expect(spans(t) == [[0, 3660, 4]])
    }

    @Test func carryInAfterGapLongerThanHeartbeat() throws {
        let r = try Rig(lastSeen: 1e9)
        try r.tier("process_minute", 86_400 - 86_400 - 3630, cpu: 9)
        let t = try #require(try r.tracks(.day, .cpu, end: 86_400).first)
        #expect(spans(t) == [[0, 30, 9]])
    }

    @Test func diskSumsReadAndWrite() throws {
        let r = try Rig(lastSeen: 1e9)
        try r.tier("process_hour", 0, diskR: 3, diskW: 4)
        let s = try #require(try r.tracks(.week, .disk, end: 3600).first?.slices.first)
        #expect(s.value == 7)
    }

    @Test func systemSeriesUsesTierForRange() throws {
        let r = try Rig(lastSeen: 0)
        try r.db.write {
            try $0.execute(sql: "INSERT INTO system_samples(ts, cpu, mem_used, pressure_level, thermal_state) VALUES (0, 10, 100, 1, 0), (5, 30, 300, 2, 1), (20, 50, 500, 1, 0)")
            try $0.execute(sql: "INSERT INTO system_minute(bucket, samples, cpu_avg, cpu_max, mem_used_avg, mem_used_max, pressure_level_max, thermal_state_max) VALUES (0, 12, 40, 90, 400, 450, 4, 2), (60, 12, 60, 90, 600, 650, 1, 0), (900, 12, 20, 90, 200, 250, 1, 0)")
        }
        let reader = HistoryReader(pool: r.pool)
        let raw = try reader.system(range: .hour, end: 3600)
        #expect(raw.map(\.bucket) == [0, 15].map { $0 + 0.0 })
        #expect(raw[0].cpu == 20 && raw[0].memUsed == 200 && raw[0].pressureLevel == 2 && raw[0].thermalState == 1)
        #expect(raw[1].cpu == 50)
        let day = try reader.system(range: .day, end: 86_400)
        #expect(day.map(\.bucket) == [0, 900])
        #expect(day[0].cpu == 50 && day[0].pressureLevel == 4 && day[0].thermalState == 2)
    }

    @Test func eventsInRangeWithApp() throws {
        let r = try Rig(lastSeen: 0)
        try r.db.write {
            try $0.execute(sql: "UPDATE processes SET app_path = '/A.app', app_name = 'A' WHERE id = ?", arguments: [r.pid])
            try $0.execute(sql: """
                INSERT INTO events(ts, kind, severity, process_id, message) VALUES
                (10, 'pressure', 2, ?, 'hi'), (20, 'thermal', 1, NULL, 'warm'), (30, 'pressure', 0, NULL, 'out')
                """, arguments: [r.pid])
        }
        let e = try HistoryReader(pool: r.pool).events(from: 10, to: 30)
        #expect(e.map(\.ts) == [10, 20])
        #expect(e[0].app == AppKey(key: "/A.app", name: "A") && e[1].app == nil)
    }
}

@Test func trackCarriesExecutablePath() throws {
    let rig = try Rig(lastSeen: 100)
    try rig.db.write { try $0.execute(sql: "UPDATE processes SET path = '/usr/bin/p' WHERE id = ?", arguments: [rig.pid]) }
    try rig.raw(10, cpu: 5)
    #expect(try rig.tracks(.hour, .cpu, end: 100).first?.path == "/usr/bin/p")
    try rig.db.write { try $0.execute(sql: "UPDATE processes SET path = NULL") }
    #expect(try rig.tracks(.hour, .cpu, end: 100).first?.path == nil)
}
