/// Paths whose rows lack a team ID, resolved with the tick's unused lookup budget. A path enters once per
/// daemon run, so no path is queued twice.
public struct TeamIDBackfill: Sendable {
    private var queue: [String] = []
    private var seen: Set<String> = []

    public init() {}

    public mutating func enqueue(_ paths: [String]) {
        for path in paths where seen.insert(path).inserted { queue.append(path) }
    }

    public mutating func take(_ n: Int) -> [String] {
        let taken = Array(queue.prefix(n))
        queue.removeFirst(taken.count)
        return taken
    }
}
