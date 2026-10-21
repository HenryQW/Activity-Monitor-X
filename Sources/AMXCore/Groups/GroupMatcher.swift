// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Foundation

public struct GroupCandidate: Sendable, Equatable {
    public let name: String
    public let path: String?
    public let bundleID: String?
    public let teamID: String?

    public init(name: String, path: String?, bundleID: String?, teamID: String?) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.teamID = teamID
    }
}

public enum GroupMatcher {
    /// False for a rule without a condition, so a group never captures every process.
    public static func matches(_ c: GroupCandidate, _ rule: GroupRule) -> Bool {
        rule.hasCondition && evaluate(rule, c)
    }

    private static func evaluate(_ rule: GroupRule, _ c: GroupCandidate) -> Bool {
        switch rule {
        case .condition(let cond): return matches(c, cond)
        case .all(let children): return !children.isEmpty && children.allSatisfy { evaluate($0, c) }
        case .any(let children): return children.contains { evaluate($0, c) }
        // A subtree without a condition matches nothing, also under `not`.
        case .not(let child): return child.hasCondition && !evaluate(child, c)
        }
    }

    private static func matches(_ c: GroupCandidate, _ cond: GroupCondition) -> Bool {
        let value = cond.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String?
        switch cond.field {
        case .name: target = c.name
        case .bundleID: target = c.bundleID
        case .path: target = c.path
        case .teamID: target = c.teamID
        }
        guard !value.isEmpty, let target else { return false }
        switch cond.op {
        case .equals: return target.caseInsensitiveCompare(value) == .orderedSame
        case .contains: return target.range(of: value, options: .caseInsensitive) != nil
        case .startsWith: return target.range(of: value, options: [.caseInsensitive, .anchored]) != nil
        }
    }
}

extension GroupRule {
    /// True when a condition with a non-empty value exists anywhere in the tree.
    public var hasCondition: Bool {
        conditions.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public enum Kind: String, CaseIterable, Sendable { case all, any, not }

    /// Nil for a condition.
    public var kind: Kind? {
        switch self {
        case .condition: return nil
        case .all: return .all
        case .any: return .any
        case .not: return .not
        }
    }

    public func with(kind: Kind) -> GroupRule {
        switch (kind, self) {
        case (.not, .not): return self
        case (.not, _): return .not(self)
        case (.all, .condition): return .all([self])
        case (.any, .condition): return .any([self])
        case (.all, _): return .all(children)
        case (.any, _): return .any(children)
        }
    }

    /// A `.not` has exactly one child; a condition has none.
    public var children: [GroupRule] {
        get {
            switch self {
            case .condition: return []
            case .all(let c), .any(let c): return c
            case .not(let c): return [c]
            }
        }
        set {
            switch self {
            case .condition: break
            case .all: self = .all(newValue)
            case .any: self = .any(newValue)
            case .not(let old): self = .not(newValue.first ?? old)
            }
        }
    }

    fileprivate var conditions: [GroupCondition] {
        if case .condition(let c) = self { return [c] }
        return children.flatMap(\.conditions)
    }
}

extension ProcessGroup {
    /// The first reason this group cannot be saved, or nil when it is valid.
    public func validationProblem(among groups: [ProcessGroup]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Name is empty" }
        if groups.contains(where: { $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A group named “\(trimmed)” exists"
        }
        let conditions = rule.conditions
        if conditions.isEmpty { return "Add at least one condition" }
        if conditions.contains(where: { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "A condition has no value"
        }
        return nil
    }
}
