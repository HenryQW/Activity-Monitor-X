import Foundation
import Testing
@testable import AMXCore

private func call(_ tool: String, _ arguments: String) throws -> [String: Any] {
    let (context, _) = try AgentFixture.make()
    let data = try AgentTools.call(tool, arguments: Data(arguments.utf8), context: context)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct AgentHistoryTests {
    @Test func topAppsRanksByAverage() throws {
        let apps = try #require(try call("top_apps", #"{"from":"-1h","limit":2}"#)["apps"] as? [[String: Any]])
        #expect(apps.map { $0["app"] as? String } == ["Safari", "Visual Studio Code"])
        #expect(abs(try #require(apps[0]["average"] as? Double) - 40) < 1e-9)
        #expect(abs(try #require(apps[1]["average"] as? Double) - 20) < 1e-9)
    }

    @Test func appHistoryUsesRawTier() throws {
        let out = try call("app_history", #"{"app":"safari","from":"-1h"}"#)
        #expect(out["bucket_seconds"] as? Double == 30)
        let points = try #require(out["points"] as? [[String: Any]])
        #expect(points.count == 120)
        #expect(points.allSatisfy { abs(($0["value"] as? Double ?? 0) - 40) < 1e-9 })
    }

    @Test func appHistoryUnknownApp() {
        #expect(throws: AgentError.invalid("unknown app: Nope")) { try call("app_history", #"{"app":"Nope"}"#) }
    }

    @Test func eventsFilterByKind() throws {
        let events = try #require(try call("events", #"{"from":"-1h","kind":"pressure"}"#)["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events.first?["app"] as? String == "mds_stores")
        #expect((try call("events", "")["events"] as? [Any])?.count == 3)
    }

    @Test func eventsToolShowsRule() throws {
        let events = try #require(try call("events", #"{"from":"-1h","kind":"alert"}"#)["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events.first?["rule"] as? String == "sustained_cpu" && events.first?["app"] as? String == "Safari")
        let steps = try #require(try call("events", #"{"from":"-1h","kind":"thermal"}"#)["events"] as? [[String: Any]])
        #expect(steps.first?["rule"] == nil)
    }

    @Test func summarizeSpan() throws {
        let out = try call("summarize", #"{"from":"-1h"}"#)
        let system = try #require(out["system"] as? [String: Any])
        #expect(system["cpu_max"] as? Double == 90)
        #expect(system["pressure_max"] as? String == "warning")
        let top = try #require(out["top"] as? [String: [[String: Any]]])
        #expect(top["cpu"]?.first?["app"] as? String == "Safari")
        #expect(out["event_counts"] as? [String: Int] == ["alert": 1, "pressure": 1, "thermal": 1])
    }

    @Test func badArguments() {
        #expect(throws: AgentError.unknownTool("nope")) { try call("nope", "{}") }
        #expect(throws: AgentError.invalid("unknown metric: ram")) { try call("top_apps", #"{"metric":"ram"}"#) }
        #expect(throws: AgentError.invalid("limit must be 1 to 50")) { try call("top_apps", #"{"limit":0}"#) }
        #expect(throws: AgentError.invalid("unknown kind: cpu")) { try call("events", #"{"kind":"cpu"}"#) }
    }
}
