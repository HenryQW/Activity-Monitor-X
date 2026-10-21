import Foundation
import Testing
@testable import AMXCore

@Suite struct GroupMatcherTests {
    private let code = GroupCandidate(
        name: "Code Helper",
        path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper",
        bundleID: "com.microsoft.VSCode", teamID: "UBF8T346G9")

    private func cond(_ field: GroupCondition.Field, _ op: GroupCondition.Op, _ value: String) -> GroupRule {
        .condition(GroupCondition(field: field, op: op, value: value))
    }

    @Test func allAnyNot() {
        #expect(GroupMatcher.matches(code, .all([cond(.name, .contains, "helper"), cond(.teamID, .equals, "ubf8t346g9")])))
        #expect(GroupMatcher.matches(code, .any([cond(.name, .equals, "x"), cond(.bundleID, .startsWith, "com.microsoft")])))
        #expect(!GroupMatcher.matches(code, .not(cond(.path, .contains, "Visual"))))
    }

    @Test func emptyNodesMatchNothing() {
        #expect(!GroupMatcher.matches(code, .all([])))
        #expect(!GroupMatcher.matches(code, .any([])))
        #expect(!GroupMatcher.matches(code, .not(.any([]))))
        #expect(!GroupMatcher.matches(code, cond(.name, .equals, "  ")))
        #expect(!GroupMatcher.matches(code, .any([cond(.name, .equals, "x"), .not(.any([]))])))
    }

    @Test func absentFieldIsNoMatch() {
        let c = GroupCandidate(name: "x", path: nil, bundleID: nil, teamID: nil)
        #expect(!GroupMatcher.matches(c, cond(.teamID, .equals, "X")))
        #expect(GroupMatcher.matches(c, .not(cond(.teamID, .equals, "X"))))
    }

    @Test func kindChanges() {
        let a = cond(.name, .equals, "a"), b = cond(.name, .equals, "b")
        #expect(GroupRule.all([a, b]).with(kind: .any) == .any([a, b]))
        #expect(GroupRule.all([a]).with(kind: .not) == .not(.all([a])))
        #expect(GroupRule.not(a).with(kind: .all) == .all([a]))
        #expect(a.with(kind: .any) == .any([a]))
        var r = GroupRule.any([a])
        r.children.append(b)
        #expect(r == .any([a, b]))
    }

    @Test func validation() {
        let ok = cond(.name, .equals, "x")
        let existing = ProcessGroup(name: "Dev", rule: .any([ok]))
        #expect(ProcessGroup(name: " ", rule: .any([ok])).validationProblem(among: []) == "Name is empty")
        #expect(ProcessGroup(name: "dev", rule: .any([ok])).validationProblem(among: [existing]) == "A group named “dev” exists")
        #expect(ProcessGroup(name: "A", rule: .any([])).validationProblem(among: []) == "Add at least one condition")
        #expect(ProcessGroup(name: "A", rule: .any([cond(.name, .equals, " ")])).validationProblem(among: []) == "A condition has no value")
        #expect(ProcessGroup(name: "A", rule: .any([ok])).validationProblem(among: [existing]) == nil)
        #expect(existing.validationProblem(among: [existing]) == nil)
    }
}
