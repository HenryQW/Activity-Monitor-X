import Foundation
import GRDB
import Testing
@testable import AMXCore

private let idA = ProcessIdentity(pid: 10, startTime: 100)
private let idB = ProcessIdentity(pid: 11, startTime: 101)

private func raw(_ id: ProcessIdentity) -> (RawProcess, AppInfo, teamID: String?) {
    (RawProcess(identity: id, name: "p\(id.pid)", path: nil, uid: 501, cpuNanos: 0, footprint: 0, diskRead: 0,
                diskWritten: 0, wakeups: 0, translated: false),
     AppInfo(appPath: nil, appName: "p\(id.pid)", bundleID: nil), nil)
}

private func sample(_ id: ProcessIdentity = idA, cpu: Double = 1, mem: UInt64 = 1_000_000) -> ProcessSample {
    ProcessSample(identity: id, cpu: cpu, mem: mem, diskR: 0, diskW: 0, energy: 0, gpu: 0, netIn: 0, netOut: 0)
}

private struct Rig {
    let path = NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
    let db: DatabaseQueue
    let writer: SampleWriter
    init(ticksPerCommit: Int = 1) throws {
        db = try Store.openWriter(path: path)
        writer = SampleWriter(db: db, path: path, ticksPerCommit: ticksPerCommit)
    }
    func tick(_ now: Double, _ p: [ProcessSample], new: [ProcessIdentity] = [], system: SystemSample = SystemSample()) throws {
        try writer.write(now: now, processes: p, newProcesses: new.map(raw), system: system)
    }
    func count(_ table: String) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }
    func lastSeen(_ id: ProcessIdentity) throws -> Double? {
        try db.read { try Double.fetchOne($0, sql: "SELECT last_seen FROM processes WHERE pid = ?", arguments: [id.pid]) }
    }
}

@Suite struct SampleWriterTests {
    @Test func firstSightingWrites() throws {
        let r = try Rig()
        try r.tick(1000, [sample()], new: [idA])
        #expect(try r.count("process_samples") == 1)
        let row = try r.db.read { try ProcessSampleRecord.fetchOne($0) }
        #expect(row?.cpu == 1 && row?.mem == 1_000_000 && row?.ts == 1000)
    }

    @Test func smallCpuChangeSkips() throws {
        let r = try Rig()
        try r.tick(1000, [sample(cpu: 1)], new: [idA])
        try r.tick(1005, [sample(cpu: 1.4)])
        #expect(try r.count("process_samples") == 1)
    }

    @Test func cpuChangeWrites() throws {
        let r = try Rig()
        try r.tick(1000, [sample(cpu: 1)], new: [idA])
        try r.tick(1005, [sample(cpu: 1.6)])
        #expect(try r.count("process_samples") == 2)
    }

    @Test func memChangeThreshold() throws {
        let r = try Rig()
        try r.tick(1000, [sample(mem: 10_000_000)], new: [idA])
        try r.tick(1005, [sample(mem: 10_524_288)])
        #expect(try r.count("process_samples") == 1)
        try r.tick(1010, [sample(mem: 10_524_289)])
        #expect(try r.count("process_samples") == 2)
    }

    @Test func ioZeroCrossingWrites() throws {
        let r = try Rig()
        try r.tick(1000, [sample()], new: [idA])
        var p = sample()
        p.netIn = 10
        try r.tick(1005, [p])
        #expect(try r.count("process_samples") == 2)
    }

    @Test func heartbeatWritesEachMinute() throws {
        let r = try Rig()
        try r.tick(119, [sample()], new: [idA])
        try r.tick(121, [sample()])
        #expect(try r.count("process_samples") == 2)
    }

    @Test func ticksCommitTogether() throws {
        let r = try Rig(ticksPerCommit: 3)
        try r.tick(1000, [sample(cpu: 1)], new: [idA])
        try r.tick(1005, [sample(cpu: 9)])
        #expect(try r.count("system_samples") == 0)
        try r.tick(1010, [sample(cpu: 9)])
        // The gate still compares each tick with the one before it.
        #expect(try [r.count("system_samples"), r.count("process_samples")] == [3, 2])
        try r.tick(1015, [sample(cpu: 1)])
        try r.writer.flush()
        #expect(try [r.count("system_samples"), r.count("process_samples")] == [4, 3])
    }

    @Test func endedProcessKeepsFirstTickOfItsLastMinute() throws {
        let r = try Rig()
        try r.tick(119, [sample()], new: [idA])
        try r.tick(121, [sample()])
        try r.tick(126, [sample()])
        #expect(try r.lastSeen(idA) == .infinity)
        // The end is written with the next minute's first tick.
        try r.tick(131, [])
        #expect(try r.lastSeen(idA) == .infinity)
        try r.tick(180, [])
        #expect(try r.lastSeen(idA) == 121)
    }

    @Test func newWriterClosesOpenProcessesAndReopensLiveOnes() throws {
        let r = try Rig()
        let idC = ProcessIdentity(pid: 12, startTime: 102)
        try r.tick(1000, [sample(idA), sample(idB)], new: [idA, idB])
        try r.tick(1065, [sample(idA), sample(idB)])
        try r.tick(1070, [sample(idA), sample(idB), sample(idC)], new: [idC])
        // Restart: the previous writer's last minute opened at 1065; C started after that.
        let writer = SampleWriter(db: r.db, path: r.path)
        #expect(try [r.lastSeen(idA), r.lastSeen(idB), r.lastSeen(idC)] == [1065, 1065, 1070])
        try writer.write(now: 1200, processes: [sample(idA)], newProcesses: [raw(idA)], system: SystemSample())
        #expect(try [r.lastSeen(idA), r.lastSeen(idB)] == [.infinity, 1065])
    }

    @Test func newWriterStartsWhenClosingFails() throws {
        let r = try Rig()
        try r.tick(1000, [sample(idA)], new: [idA])
        // As on a full disk, the close's UPDATE fails; the writer still starts and A stays open.
        var config = Configuration()
        config.readonly = true
        _ = SampleWriter(db: try DatabaseQueue(path: r.path, configuration: config), path: r.path)
        #expect(try r.lastSeen(idA) == .infinity)
    }

    @Test func systemRowAlwaysWritten() throws {
        let r = try Rig()
        for t in [1000.0, 1005, 1010] { try r.tick(t, []) }
        #expect(try r.count("system_samples") == 3)
        var s = SystemSample()
        s.tempCPU = 55
        s.memUsed = 42
        try r.tick(1015, [], system: s)
        let row = try r.db.read { try SystemSampleRecord.fetchOne($0, sql: "SELECT * FROM system_samples WHERE ts = 1015") }
        #expect(row?.tempCpu == 55 && row?.memUsed == 42 && row?.pressureLevel == 1)
    }

    @Test func writesDiskFree() throws {
        let r = try Rig()
        var s = SystemSample()
        s.diskFree = 42
        try r.tick(1000, [], system: s)
        try r.tick(1005, [])
        let free = try r.db.read { try Row.fetchAll($0, sql: "SELECT disk_free FROM system_samples ORDER BY ts").map { $0[0] as Int64? } }
        #expect(free == [42, nil])
    }

    @Test func draftsCarryProcessID() throws {
        let r = try Rig()
        let unknown = ProcessIdentity(pid: 99, startTime: 1)
        let drafts = [idA, unknown].map {
            EventDraft(ts: 1000, kind: EventKind.alert, severity: 1, identity: $0, rule: "memory_jump",
                       message: "p jumped by 1.5 GB", value: 1_610_612_736)
        }
        try r.writer.write(now: 1000, processes: [sample()], newProcesses: [raw(idA)], system: SystemSample(),
                           events: drafts)
        let rows = try r.db.read { try EventRecord.fetchAll($0, sql: "SELECT * FROM events ORDER BY id") }
        let idOfA = try r.db.read { try Int64.fetchOne($0, sql: "SELECT id FROM processes WHERE pid = 10") }
        #expect(rows.map(\.processId) == [idOfA, nil])
        #expect(rows.allSatisfy { $0.rule == "memory_jump" && $0.value == 1_610_612_736 && $0.message == "p jumped by 1.5 GB" })
    }

    @Test func failedWriteKeepsDrafts() throws {
        let r = try Rig()
        func draft(_ ts: Double, _ id: ProcessIdentity?) -> EventDraft {
            EventDraft(ts: ts, kind: EventKind.thermal, severity: 2, identity: id, rule: nil, message: "m", value: 2)
        }
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
        #expect(throws: StoreError.self) {
            try r.writer.write(now: 1000, processes: [sample()], newProcesses: [raw(idA)], system: SystemSample(),
                               events: [draft(1000, idA)])
        }
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 0") }
        try r.writer.write(now: 1005, processes: [sample()], newProcesses: [], system: SystemSample(),
                           events: [draft(1005, nil)])
        let rows = try r.db.read { try EventRecord.fetchAll($0, sql: "SELECT * FROM events ORDER BY id") }
        let idOfA = try r.db.read { try Int64.fetchOne($0, sql: "SELECT id FROM processes WHERE pid = 10") }
        #expect(rows.map(\.ts) == [1000, 1005] && rows.map(\.processId) == [idOfA, nil])
    }

    @Test func failedWriteKeepsNewProcesses() throws {
        let r = try Rig()
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
        #expect(throws: StoreError.self) { try r.tick(1000, [sample(idA), sample(idB)], new: [idA, idB]) }
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 0") }
        // The sampler reports a process as new only once; B has vanished since.
        try r.tick(1005, [sample(idA)])
        let pids = try r.db.read { try Int32.fetchAll($0, sql: "SELECT pid FROM processes") }
        #expect(pids == [idA.pid])
        let row = try r.db.read { try ProcessSampleRecord.fetchOne($0) }
        #expect(row?.ts == 1005 && row?.cpu == 1)
    }

    @Test func vanishedIdentityIsDropped() throws {
        let r = try Rig()
        try r.tick(1000, [sample(idA), sample(idB)], new: [idA, idB])
        #expect(r.writer.ids.count == 2)
        try r.tick(1005, [sample(idA)])
        #expect(r.writer.ids.keys.sorted { $0.pid < $1.pid } == [idA])
    }

    @Test func failedBatchCarriesPathAndKeepsNewProcesses() throws {
        let r = try Rig(ticksPerCommit: 2)
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
        try r.tick(1000, [sample(idA), sample(idB)], new: [idA])
        do {
            try r.tick(1005, [sample(idA), sample(idB)], new: [idB])
            Issue.record("expected failure")
        } catch let error as StoreError {
            #expect(error.description.contains(r.path))
        }
        try r.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 0") }
        // New processes of both failed ticks are written with the next commit.
        try r.tick(1010, [sample(idA), sample(idB)])
        try r.writer.flush()
        let pids = try r.db.read { try Int32.fetchAll($0, sql: "SELECT pid FROM processes ORDER BY pid") }
        #expect(pids == [idA.pid, idB.pid])
    }
}
