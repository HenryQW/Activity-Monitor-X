import Foundation
import GRDB
import Testing
@testable import AMXCore

@Suite struct TeamIDBackfillTests {
    private func rig(_ rows: [(path: String?, team: String?)]) throws -> (DatabaseQueue, SampleWriter) {
        let path = NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
        let db = try Store.openWriter(path: path)
        let writer = try SampleWriter(db: db, path: path)
        try db.write { db in
            for (i, row) in rows.enumerated() {
                try ProcessRecord(pid: Int32(i + 1), startTime: 1, name: "p", path: row.path, teamId: row.team,
                                  translated: false, firstSeen: 1, lastSeen: 2).insert(db)
            }
        }
        return (db, writer)
    }

    @Test func queueDedupesAndTakesInOrder() {
        var q = TeamIDBackfill()
        q.enqueue(["/a", "/b", "/a"])
        #expect(q.take(1) == ["/a"])
        #expect(q.take(5) == ["/b"])
        q.enqueue(["/a"])
        #expect(q.take(5) == [])
    }

    @Test func pathsWithoutTeamIDAreDistinct() throws {
        let (_, writer) = try rig([("/a", nil), ("/a", nil), ("/b", "T"), (nil, nil)])
        #expect(try writer.pathsWithoutTeamID() == ["/a"])
    }

    @Test func backfillFillsOnlyNullRows() throws {
        let (db, writer) = try rig([("/a", nil), ("/a", "OLD"), ("/b", nil)])
        writer.backfillTeamIDs(["/a": "TEAM1"])
        try writer.flush()
        let teams = try db.read { try String?.fetchAll($0, sql: "SELECT team_id FROM processes ORDER BY pid") }
        #expect(teams == ["TEAM1", "OLD", nil])
    }
}
