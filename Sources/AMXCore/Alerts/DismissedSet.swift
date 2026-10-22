/// Alert ids the user dismissed, newest dismissals kept up to `limit`.
public struct DismissedSet: Equatable, Sendable {
    public static let limit = 10_000
    /// Oldest dismissal first.
    public private(set) var ids: [Int64]
    private var members: Set<Int64>

    public init(ids: [Int64] = []) {
        self.ids = []
        members = []
        ids.forEach { insert($0) }
    }

    public func contains(_ id: Int64) -> Bool { members.contains(id) }

    public mutating func insert(_ id: Int64) {
        guard members.insert(id).inserted else { return }
        ids.append(id)
        if ids.count > Self.limit { members.remove(ids.removeFirst()) }
    }

    public mutating func remove(_ id: Int64) {
        guard members.remove(id) != nil else { return }
        ids.removeAll { $0 == id }
    }
}
