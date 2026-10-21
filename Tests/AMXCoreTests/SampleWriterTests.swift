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
    init() throws {
        db = try Store.openWriter(path: path)
        writer = SampleWriter(db: db, path: path)
    }
    func tick(_ now: Double, _ p: [ProcessSample], new: [ProcessIdentity] = [], system: SystemSample = SystemSample()) throws {
        try writer.write(now: now, processes: p, newProcesses: new.map(raw), system: system)
    }
    func count(_ table: String) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
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
        let lastSeen = try r.db.read { try Double.fetchOne($0, sql: "SELECT last_seen FROM processes") }
        #expect(lastSeen == 121)
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

    @Test func pressureEventOnlyOnChange() throws {
        let r = try Rig()
        try r.tick(1000, [sample(idA, mem: 5), sample(idB, mem: 9)], new: [idA, idB])
        var t = 1005.0
        for level in [1, 1, 2, 2, 4] {
            var s = SystemSample()
            s.pressureLevel = level
            try r.tick(t, [sample(idA, mem: 5), sample(idB, mem: 9)], system: s)
            t += 5
        }
        let events = try r.db.read { try EventRecord.fetchAll($0, sql: "SELECT * FROM events ORDER BY id") }
        #expect(events.count == 2)
        #expect(events.map(\.severity) == [1, 2])
        let topId = try r.db.read { try Int64.fetchOne($0, sql: "SELECT id FROM processes WHERE pid = 11") }
        #expect(events.last?.processId == topId)
        #expect(events.last?.kind == "pressure" && events.last?.message == "Memory pressure critical")
    }

    @Test func thermalEventOnChange() throws {
        let r = try Rig()
        try r.tick(1000, [])
        var s = SystemSample()
        s.thermalState = 2
        try r.tick(1005, [], system: s)
        let e = try r.db.read { try EventRecord.fetchOne($0) }
        #expect(e?.kind == "thermal" && e?.severity == 2 && e?.processId == nil)
    }

    @Test func writeFailureCarriesPath() throws {
        let path = NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
        _ = try Store.openWriter(path: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        var config = Configuration()
        config.readonly = true
        let db = try DatabaseQueue(path: path, configuration: config)
        let writer = SampleWriter(db: db, path: path)
        do {
            try writer.write(now: 1, processes: [], newProcesses: [], system: SystemSample())
            Issue.record("expected failure")
        } catch let error as StoreError {
            #expect(error.description.contains(path))
        }
    }
}
