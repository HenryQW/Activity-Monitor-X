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
        #expect(applied == ["v1"])
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
