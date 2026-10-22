/// The result of one Disk Map scan. Children are values, so a folded subtree frees its memory at once.
public struct DiskTree: Sendable {
    public struct Node: Sendable, Identifiable {
        public enum Kind: Sendable { case folder, file, smaller, refused }
        public let name: String
        public let kind: Kind
        /// Allocated bytes; a folder's size is the sum of its children.
        public var size: UInt64
        /// Entries this node stands for, itself and all entries inside; for `smaller`, all the folded ones.
        public var items: Int
        /// Size descending.
        public var children: [Node]
        /// Nodes in this subtree, this one included.
        public var count: Int
        /// Names are unique among siblings.
        public var id: String { name }
    }

    public let rootPath: String
    public var root: Node
    /// The first 200 folders the scan could not read.
    public var refused: [String]
    public var refusedCount: Int
    /// The scan stopped before the end.
    public var partial: Bool
    /// The node cap folded items that the per-folder rule would keep.
    public var simplified: Bool

    public subscript(path: [Int]) -> Node { path.reduce(root) { $0.children[$1] } }
}

public struct DiskScanLimits: Sendable {
    /// Hard cap on live nodes.
    public var maxNodes = 300_000
    public var keepPerFolder = 100
    public var minNodeBytes: UInt64 = 1 << 20
    public init() {}
}

public struct DiskScanProgress: Sendable {
    public let items: Int
    public let bytes: UInt64
    public let folder: String
}
