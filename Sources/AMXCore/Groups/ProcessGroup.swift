import Foundation

public struct ProcessGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var color: GroupColor
    public var rule: GroupRule

    public init(id: UUID = UUID(), name: String, symbol: String = "folder", color: GroupColor = .blue,
                rule: GroupRule = .any([])) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.rule = rule
    }
}

public enum GroupColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
}

public struct GroupCondition: Codable, Sendable, Hashable {
    public enum Field: String, Codable, Sendable, CaseIterable {
        case name, bundleID = "bundle_id", path, teamID = "team_id"
    }

    public enum Op: String, Codable, Sendable, CaseIterable {
        case equals = "is", contains, startsWith = "starts_with"
    }

    public var field: Field
    public var op: Op
    public var value: String

    public init(field: Field, op: Op, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }
}

/// JSON shapes: `{"all":[…]}`, `{"any":[…]}`, `{"not":{…}}`, or a condition `{"field":…,"op":…,"value":…}`.
public indirect enum GroupRule: Codable, Sendable, Hashable {
    case condition(GroupCondition)
    case all([GroupRule])
    case any([GroupRule])
    case not(GroupRule)

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static let conditionKeys: Set<String> = ["field", "op", "value"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let keys = Set(c.allKeys.map(\.stringValue))
        switch keys {
        case ["all"]: self = .all(try c.decode([GroupRule].self, forKey: Key("all")))
        case ["any"]: self = .any(try c.decode([GroupRule].self, forKey: Key("any")))
        case ["not"]: self = .not(try c.decode(GroupRule.self, forKey: Key("not")))
        case Self.conditionKeys: self = .condition(try GroupCondition(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Unknown rule shape, keys: \(keys.sorted())"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .condition(let condition): try condition.encode(to: encoder)
        case .all(let rules):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(rules, forKey: Key("all"))
        case .any(let rules):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(rules, forKey: Key("any"))
        case .not(let rule):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(rule, forKey: Key("not"))
        }
    }
}
