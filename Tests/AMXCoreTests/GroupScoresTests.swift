import Foundation
import Testing
@testable import AMXCore

@Suite struct GroupScoresTests {
    @Test func groupAverageSumsMembers() {
        func track(_ name: String, _ value: Double) -> ProcessTrack {
            ProcessTrack(processID: 0, pid: 1, startTime: 0, name: name, app: AppKey(key: name, name: name),
                         slices: [Slice(start: 0, end: 10, value: value)])
        }
        let tracks = [track("a", 10), track("b", 20), track("c", 5)]
        func cond(_ n: String) -> GroupRule { .condition(GroupCondition(field: .name, op: .equals, value: n)) }
        let ab = ProcessGroup(name: "ab", rule: .any([cond("a"), cond("b")]))
        let empty = ProcessGroup(name: "empty", rule: .any([]))
        let averages = GroupScores.averages(tracks, groups: [ab, empty], from: 0, to: 10)
        #expect(averages == [ab.id: 30, empty.id: 0])
    }
}
