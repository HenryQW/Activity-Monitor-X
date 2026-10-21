import Foundation
import Testing
@testable import AMXCore

private func send(_ line: String, context: AgentContext? = nil) throws -> [String: Any] {
    let reply = try #require(MCPHandler.handle(line: line, context: context ?? AgentFixture.make().0))
    #expect(!reply.contains("\n"))
    let object = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    #expect(object["jsonrpc"] as? String == "2.0")
    return object
}

private func request(_ id: Int, _ method: String, _ params: String = "{}") -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#
}

private func toolResult(_ name: String, _ arguments: String) throws -> (text: String, isError: Bool) {
    let result = try #require(try send(request(3, "tools/call", #"{"name":"\#(name)","arguments":\#(arguments)}"#))["result"]
        as? [String: Any])
    let content = try #require(result["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "text")
    return (try #require(content.first?["text"] as? String), try #require(result["isError"] as? Bool))
}

@Suite struct MCPHandlerTests {
    @Test(arguments: [("2025-03-26", "2025-03-26"), ("2024-11-05", "2024-11-05"), ("1999-01-01", "2025-06-18")])
    func initializeNegotiatesVersion(asked: String, answered: String) throws {
        let out = try send(request(1, "initialize", #"{"protocolVersion":"\#(asked)","capabilities":{}}"#))
        #expect(out["id"] as? Int == 1)
        let result = try #require(out["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == answered)
        #expect((result["capabilities"] as? [String: [String: Bool]]) == ["tools": ["listChanged": false]])
        #expect((result["serverInfo"] as? [String: String]) == ["name": "amx", "version": "0.3.0"])
    }

    @Test func toolsList() throws {
        let tools = try #require((try send(request(2, "tools/list"))["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String })
            == ["summarize", "top_apps", "app_history", "events", "list_groups", "group_summary", "query"])
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
    }

    @Test func toolsCall() throws {
        let ok = try toolResult("top_apps", #"{"from":"-1h","limit":2}"#)
        #expect(!ok.isError)
        let apps = try #require((try JSONSerialization.jsonObject(with: Data(ok.text.utf8)) as? [String: Any])?["apps"]
            as? [[String: Any]])
        #expect(apps.map { $0["app"] as? String } == ["Safari", "Visual Studio Code"])

        let failed = try toolResult("group_summary", #"{"group":"x"}"#)
        #expect(failed == ("unknown group: x", true))
    }

    @Test func notificationAndClientReplyGetNoReply() throws {
        let context = try AgentFixture.make().0
        #expect(MCPHandler.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, context: context) == nil)
        #expect(MCPHandler.handle(line: #"{"jsonrpc":"2.0","id":7,"result":{}}"#, context: context) == nil)
    }

    @Test func errors() throws {
        let unknown = try send(request(4, "resources/list"))
        #expect(unknown["id"] as? Int == 4)
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)

        let tool = try send(request(5, "tools/call", #"{"name":"nope"}"#))
        #expect((tool["error"] as? [String: Any])?["code"] as? Int == -32602)

        let parse = try send(#"{"jsonrpc":"2.0","id":6,"#)
        #expect(parse["id"] is NSNull)
        #expect((parse["error"] as? [String: Any])?["code"] as? Int == -32700)

        let nullID = try send(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#)
        #expect((nullID["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(MCPHandler.handle(line: "  ", context: try AgentFixture.make().0) == nil)
    }

    @Test func ping() throws {
        let out = try send(request(8, "ping"))
        #expect((out["result"] as? [String: Any])?.isEmpty == true)
    }
}
