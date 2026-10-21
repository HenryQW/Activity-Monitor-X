import Foundation

public enum GroupScores {
    public static func members(_ tracks: [ProcessTrack], of group: ProcessGroup) -> [ProcessTrack] {
        tracks.filter { GroupMatcher.matches($0.candidate, group.rule) }
    }

    /// Every group gets a key. A group's value is the sum of its members' time-weighted averages over [from, to).
    public static func averages(_ tracks: [ProcessTrack], groups: [ProcessGroup], from: Double, to: Double) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: groups.map { group in
            (group.id, members(tracks, of: group).reduce(0) { $0 + $1.average(from: from, to: to) })
        })
    }
}
