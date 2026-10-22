import Foundation

/// MCP over stdio: one JSON-RPC 2.0 message per line in, one reply line out.
public enum MCPHandler {
    static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private struct Failure: Error {
        let code: Int
        let message: String
    }

    /// Returns nil for a blank line, a notification (no `id`) and a client's reply to a request.
    public static func handle(line: String, context: AgentContext) -> String? {
        if line.allSatisfy(\.isWhitespace) { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: .fragmentsAllowed) else {
            return reply(NSNull(), ["error": ["code": -32700, "message": "parse error"]])
        }
        guard let message = json as? [String: Any] else {
            return reply(NSNull(), ["error": ["code": -32600, "message": "invalid request"]])
        }
        // A number no Double holds (such as -1e400) parses to an infinity that JSONSerialization cannot write.
        guard JSONSerialization.isValidJSONObject(message) else {
            return reply(NSNull(), ["error": ["code": -32700, "message": "parse error"]])
        }
        guard let id = message["id"], message["result"] == nil, message["error"] == nil else { return nil }
        guard let method = message["method"] as? String, !(id is NSNull) else {
            return reply(id, ["error": ["code": -32600, "message": "invalid request"]])
        }
        do {
            return reply(id, ["result": try result(method, message["params"] as? [String: Any] ?? [:], context)])
        } catch {
            return reply(id, ["error": ["code": error.code, "message": error.message]])
        }
    }

    private static func result(_ method: String, _ params: [String: Any], _ context: AgentContext) throws(Failure) -> Any {
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return ["protocolVersion": versions.contains(asked) ? asked : versions[0],
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "amx", "version": AMX.version]]
        case "ping":
            return [String: Any]()
        case "tools/list":
            return ["tools": AgentTools.catalog.map { spec in
                ["name": spec.name, "description": spec.description,
                 "inputSchema": try! JSONSerialization.jsonObject(with: Data(spec.inputSchema.utf8))]
            }]
        case "tools/call":
            guard let name = params["name"] as? String, AgentTools.catalog.contains(where: { $0.name == name }) else {
                throw Failure(code: -32602, message: "unknown tool: \(params["name"] ?? "")")
            }
            let arguments = params["arguments"] ?? [String: Any]()
            guard arguments is [String: Any] else { throw Failure(code: -32602, message: "arguments must be an object") }
            do {
                let data = try AgentTools.call(name, arguments: JSONSerialization.data(withJSONObject: arguments),
                                               context: context)
                return text(String(decoding: data, as: UTF8.self), isError: false)
            } catch {
                return text("\(error)", isError: true)
            }
        default:
            throw Failure(code: -32601, message: "method not found: \(method)")
        }
    }

    private static func text(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func reply(_ id: Any, _ body: [String: Any]) -> String {
        var body = body
        (body["jsonrpc"], body["id"]) = ("2.0", id)
        // `data` raises an exception, not an error, for an object it cannot write.
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return #"{"error":{"code":-32603,"message":"internal error"},"id":null,"jsonrpc":"2.0"}"# }
        return String(decoding: data, as: UTF8.self)
    }
}
