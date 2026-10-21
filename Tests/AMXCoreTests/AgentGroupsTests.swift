import Foundation
import GRDB
import Testing
@testable import AMXCore

private func call(_ tool: String, _ arguments: String, context: AgentContext? = nil) throws -> [String: Any] {
    let context = try context ?? AgentFixture.make().0
    let data = try AgentTools.call(tool, arguments: Data(arguments.utf8), context: context)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func rows(_ sql: String) throws -> (rows: [[Any]], truncated: Bool) {
    let arguments = String(data: try JSONSerialization.data(withJSONObject: ["sql": sql]), encoding: .utf8)!
    let out = try call("query", arguments)
    return (try #require(out["rows"] as? [[Any]]), try #require(out["truncated"] as? Bool))
}

@Suite struct AgentGroupsTests {
    @Test func listGroupsScoresNow() throws {
        let groups = try #require(try call("list_groups", "{}")["groups"] as? [[String: Any]])
        #expect(groups.map { $0["name"] as? String } == ["Dev", "Browsers"])
        #expect(abs(try #require(groups[0]["score_now"] as? Double) - 4.125) < 1e-9)
        #expect(abs(try #require(groups[1]["score_now"] as? Double) - 8.25) < 1e-9)
        let rule = try JSONDecoder().decode(GroupRule.self, from: JSONSerialization.data(withJSONObject: groups[0]["rule"]!))
        #expect(rule == .condition(GroupCondition(field: .teamID, op: .equals, value: "UBF8T346G9")))
    }

    @Test func groupSummaryShares() throws {
        let out = try call("group_summary", #"{"group":"dev","from":"-1h"}"#)
        #expect(out["group"] as? String == "Dev")
        let points = try #require(out["points"] as? [[String: Any]])
        #expect(points.count == 120)
        #expect(points.allSatisfy { abs(($0["value"] as? Double ?? 0) - 4.125) < 1e-9 })
        let members = try #require(out["members"] as? [[String: Any]])
        #expect(members.map { $0["app"] as? String } == ["Visual Studio Code"])
        #expect(members.first?["share"] as? Double == 1)
    }

    @Test func groupSummaryUnknown() {
        #expect(throws: AgentError.invalid("unknown group: x")) { try call("group_summary", #"{"group":"x"}"#) }
    }

    @Test func groupsFileErrorSurfaces() throws {
        let (fixture, pool) = try AgentFixture.make()
        let context = AgentContext(pool: pool, groups: { throw GroupStoreError.unsupportedVersion(2) },
                                   device: fixture.device, now: fixture.now)
        #expect(throws: GroupStoreError.unsupportedVersion(2)) { try call("list_groups", "{}", context: context) }
    }

    @Test func queryReads() throws {
        let out = try rows("SELECT name FROM processes ORDER BY name")
        #expect(out.rows.map { $0.compactMap { $0 as? String } } == [["Code Helper"], ["Safari"], ["mds_stores"]])
        #expect(!out.truncated)
    }

    @Test func queryView() throws {
        let out = try rows("SELECT app, cpu FROM v_raw WHERE app = 'Safari' LIMIT 1")
        #expect(out.rows.count == 1)
        #expect(out.rows.first?.first as? String == "Safari")
        #expect(out.rows.first?.last as? Double == 40)
    }

    @Test func queryRefusesWrites() throws {
        let (context, pool) = try AgentFixture.make()
        #expect(throws: AgentError.invalid("query must be read-only")) {
            try call("query", #"{"sql":"WITH x AS (SELECT 1) DELETE FROM processes"}"#, context: context)
        }
        #expect(throws: AgentError.self) { try call("query", #"{"sql":"COMMIT"}"#, context: context) }
        #expect(try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM processes") } == 3)
    }

    @Test func queryCapsRows() throws {
        let out = try rows("WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1500) SELECT i FROM n")
        #expect(out.rows.count == 1000)
        #expect(out.truncated)
    }

    @Test func queryLimits() throws {
        let (context, _) = try AgentFixture.make()
        #expect(throws: AgentError.invalid("query must be one statement")) {
            try call("query", #"{"sql":"SELECT 1; SELECT 2"}"#, context: context)
        }
        let notSelect = AgentError.invalid("query must be a SELECT, WITH or VALUES statement")
        #expect(throws: notSelect) { try call("query", #"{"sql":"ATTACH DATABASE ':memory:' AS x"}"#, context: context) }
        #expect(throws: AgentError.invalid("string or blob too big")) {
            try call("query", #"{"sql":"SELECT zeroblob(2000000000)"}"#, context: context)
        }
        // One connection: a refused PRAGMA leaves it unchanged, and it still reads after a timeout.
        let (caseInsensitiveLike, afterTimeout) = try context.pool.read { db in
            #expect(throws: notSelect) { try AgentSQL.run(" -- c\n /* PRAGMA */ PRAGMA case_sensitive_like=1", db) }
            #expect(throws: AgentError.invalid("query must be one statement")) {
                try AgentSQL.run("SELECT 1; PRAGMA case_sensitive_like=1", db)
            }
            let like = try Bool.fetchOne(db, sql: "SELECT 'a' LIKE 'A'")
            #expect(throws: AgentError.invalid("query took longer than 0.2 s")) {
                try AgentSQL.run("WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) SELECT COUNT(*) FROM n",
                                 db, limit: 0.2)
            }
            return (like, try AgentSQL.run("SELECT 1", db).rows.count)
        }
        #expect(caseInsensitiveLike == true)
        #expect(afterTimeout == 1)
        #expect(try rows("SELECT 1; -- c").rows.count == 1)
        #expect(try rows("SELECT 1;;").rows.count == 1)
        #expect(try rows("SELECT x'00ff'").rows.first?.first as? String == "AP8=")
        // An open process's last_seen is +inf, which JSON cannot hold.
        let open = try rows("SELECT last_seen FROM processes WHERE name = 'Safari'")
        #expect(open.rows.first?.first is NSNull)
    }
}
