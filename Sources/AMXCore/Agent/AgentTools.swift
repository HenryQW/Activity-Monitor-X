import Foundation
import GRDB

/// What every agent tool reads: the history database, the user's groups, this Mac and the clock.
public struct AgentContext: Sendable {
    public let pool: DatabasePool
    public let groups: @Sendable () throws -> [ProcessGroup]
    public let device: Device
    public let now: @Sendable () -> Double

    public init(pool: DatabasePool, groups: @escaping @Sendable () throws -> [ProcessGroup], device: Device = .current,
                now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        (self.pool, self.groups, self.device, self.now) = (pool, groups, device, now)
    }

    var reader: HistoryReader { HistoryReader(pool: pool, device: device) }
}

/// The tools the `amx` CLI and the MCP handler share: JSON arguments in, JSON out.
public enum AgentTools {
    public struct Spec: Sendable {
        public let name: String
        public let description: String
        /// A JSON Schema object.
        public let inputSchema: String
    }

    struct Tool: Sendable {
        let spec: Spec
        let run: @Sendable (Data, AgentContext) throws -> Data

        /// Arguments decode into `A` (unknown keys ignored); the result encodes with `encode`.
        init<A: Decodable & Sendable, R: Encodable & Sendable>(_ name: String, _ description: String, schema: String,
                                          _ body: @escaping @Sendable (A, AgentContext) throws -> R) {
            spec = Spec(name: name, description: description, inputSchema: schema)
            run = { data, context in
                let arguments: A
                do {
                    arguments = try JSONDecoder().decode(A.self, from: data)
                } catch let error as DecodingError {
                    throw AgentError.invalid("bad arguments: \(error.summary)")
                }
                return try AgentTools.encode(try body(arguments, context))
            }
        }
    }

    static let tools: [Tool] = AgentHistory.tools + AgentGroups.tools + [AgentSQL.query]

    public static let catalog: [Spec] = tools.map(\.spec)

    /// Empty `arguments` reads as `{}`. Every error a tool throws is an `AgentError`, except a failed output encoding.
    public static func call(_ name: String, arguments: Data, context: AgentContext) throws -> Data {
        guard let tool = tools.first(where: { $0.spec.name == name }) else { throw AgentError.unknownTool(name) }
        do {
            return try tool.run(arguments.isEmpty ? Data("{}".utf8) : arguments, context)
        } catch let error as DatabaseError {
            throw AgentError.invalid(error.message ?? "\(error.resultCode)")
        }
    }

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    // MARK: Arguments shared by the tools

    /// A time argument: a string for `TimeArg`, or a number of Unix seconds.
    struct Time: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self) { text = String(seconds) } else { text = try c.decode(String.self) }
        }
    }

    /// `from` defaults to `-24h`, `to` to `now`; `to` is clamped to `now`.
    static func window(from: Time?, to: Time?, context: AgentContext) throws -> QueryWindow {
        let now = context.now()
        return try QueryWindow.resolve(from: TimeArg.parse(from?.text ?? "-24h", now: now),
                                       to: min(TimeArg.parse(to?.text ?? "now", now: now), now), now: now)
    }

    static func metric(_ name: String?) throws -> Metric {
        guard let metric = Metric(rawValue: name ?? "cpu") else { throw AgentError.invalid("unknown metric: \(name!)") }
        return metric
    }

    // MARK: Schema and description fragments

    static let units = "Units: " + Metric.allCases.map { "\($0.rawValue) \($0.unit)" }.joined(separator: "; ") + "."
    static let times = "Input times: ISO 8601, Unix seconds or relative (now, -30s, -90m, -24h, -7d). Output times: ISO 8601 UTC."

    static let timeProperties = """
        "from":{"type":["string","number"],"description":"Window start; default -24h"},\
        "to":{"type":["string","number"],"description":"Window end; default now, later values clamp to now"}
        """
    static func metricProperty(default metric: Metric = .cpu) -> String {
        """
        "metric":{"type":"string","enum":[\(Metric.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ","))],"default":"\(metric.rawValue)"}
        """
    }

    static func schema(_ properties: [String], required: [String] = []) -> String {
        #"{"type":"object","properties":{"# + properties.joined(separator: ",") + #"},"required":["#
            + required.map { "\"\($0)\"" }.joined(separator: ",") + "]}"
    }
}

private extension DecodingError {
    var summary: String {
        let context: Context
        switch self {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c): context = c
        @unknown default: return "\(self)"
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
