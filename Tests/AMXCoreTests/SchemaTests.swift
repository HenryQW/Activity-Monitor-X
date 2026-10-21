import Foundation
import GRDB
import Testing
@testable import AMXCore

private func tempDB() -> String {
    NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
}

private let tables = ["processes", "process_samples", "process_minute", "process_hour",
                      "system_samples", "system_minute", "system_hour", "events", "meta"]

@Suite struct SchemaTests {
    @Test func migrateCreatesTables() throws {
        let writer = try Store.openWriter(path: tempDB())
        let found = try writer.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type='table'") }
        #expect(found.isSuperset(of: tables))
    }

    @Test func writerSetsPragmas() throws {
        let writer = try Store.openWriter(path: tempDB())
        let (mode, vacuum, applied) = try writer.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"),
             try Int.fetchOne(db, sql: "PRAGMA auto_vacuum"),
             try Schema.migrator.appliedIdentifiers(db))
        }
        #expect(mode == "wal")
        #expect(vacuum == 2)
        #expect(applied == ["v1", "v2"])
    }

    @Test func v2KeepsRawAndTierRows() throws {
        let path = tempDB()
        let v1 = try DatabaseQueue(path: path)
        try Schema.migrator.migrate(v1, upTo: "v1")
        try v1.write {
            try $0.execute(sql: """
                INSERT INTO processes(id, pid, start_time, name, translated, first_seen, last_seen) VALUES (1, 1, 0, 'p', 0, 0, 0);
                INSERT INTO process_samples(process_id, ts, cpu, net_out) VALUES (1, 10, 1, 7), (1, 5, 2, NULL);
                INSERT INTO process_minute(process_id, bucket, samples, cpu_avg, net_out_max) VALUES (1, 60, 60, 3, 8);
                INSERT INTO process_hour(process_id, bucket, samples, mem_max) VALUES (1, 3600, 60, 4);
                """)
        }
        try v1.close()
        let rows = try Store.openWriter(path: path).read { db in
            try [
                "SELECT process_id, ts, cpu, net_out FROM process_samples",
                "SELECT process_id, bucket, samples, cpu_avg, net_out_max FROM process_minute",
                "SELECT process_id, bucket, samples, mem_max FROM process_hour",
            ].map { try Row.fetchAll(db, sql: $0).map { $0.description } }
        }
        #expect(rows == [
            ["[process_id:1 ts:5.0 cpu:2.0 net_out:NULL]", "[process_id:1 ts:10.0 cpu:1.0 net_out:7.0]"],
            ["[process_id:1 bucket:60.0 samples:60 cpu_avg:3.0 net_out_max:8.0]"],
            ["[process_id:1 bucket:3600.0 samples:60 mem_max:4.0]"],
        ])
    }

    @Test func reopenIsIdempotent() throws {
        let path = tempDB()
        let count = { (w: DatabaseQueue) in
            try w.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master") }
        }
        let first = try count(Store.openWriter(path: path))
        let second = try count(Store.openWriter(path: path))
        #expect(first == second)
    }

    @Test func readerCannotWrite() throws {
        let path = tempDB()
        _ = try Store.openWriter(path: path)
        let reader = try Store.openReader(path: path)
        #expect(throws: (any Error).self) {
            try reader.write { try MetaRecord(key: "k", value: 1).insert($0) }
        }
    }

    @Test func recordRoundTrip() throws {
        let path = tempDB()
        let writer = try Store.openWriter(path: path)
        try writer.write {
            try ProcessRecord(id: nil, pid: 42, startTime: 1.5, name: "x", path: nil, appPath: nil, appName: nil,
                              bundleId: "b", teamId: nil, uid: 501, translated: false, firstSeen: 1, lastSeen: 2).insert($0)
        }
        let rec = try Store.openReader(path: path).read { try ProcessRecord.filter(Column("pid") == 42).fetchOne($0) }
        #expect(rec?.name == "x" && rec?.bundleId == "b" && rec?.id != nil)
    }
}
