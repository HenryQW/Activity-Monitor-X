/// The menu bar popover's top apps from one Live snapshot.
public enum LiveTop {
    public struct Row: Sendable, Equatable {
        public let app: AppKey
        public let cpu: Double
        public let mem: UInt64
    }

    /// Process CPU and memory summed per app, CPU descending, ties by name.
    public static func apps(_ s: LiveSnapshot, limit: Int) -> [Row] {
        var sums: [String: Row] = [:]
        for p in s.processes {
            let old = sums[p.appKey]
            sums[p.appKey] = Row(app: AppKey(key: p.appKey, name: p.appName), cpu: (old?.cpu ?? 0) + p.cpu,
                                 mem: (old?.mem ?? 0) + p.mem)
        }
        return Array(sums.values.sorted { ($0.cpu, $1.app.name) > ($1.cpu, $0.app.name) }.prefix(limit))
    }
}
