/// Paths whose rows lack a team ID, resolved with the tick's unused lookup budget. A path is queued at most once
/// until the queue drains; then `seen` is cleared, so it does not grow for the whole daemon run.
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
        if queue.isEmpty { seen = [] }
        return taken
    }
}
