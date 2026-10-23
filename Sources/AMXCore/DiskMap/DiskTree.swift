/// The result of one Disk Map scan. Children are values, so a folded subtree frees its memory at once.
public struct DiskTree: Sendable {
    public struct Node: Sendable, Identifiable {
        public enum Kind: Sendable { case folder, file, smaller, refused }
        public var name: String
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

    /// Drops the item and takes its size, items and nodes off every folder above it. A non-empty path.
    public mutating func remove(at path: [Int]) { _ = Self.remove(&root, path[...]) }

    /// Renames the item; the order stays, as it depends on size only. A non-empty path.
    public mutating func rename(at path: [Int], to name: String) {
        var node = self[path]
        node.name = name
        Self.replace(&root, path[...], node)
    }

    private static func remove(_ node: inout Node, _ path: ArraySlice<Int>) -> Node {
        let gone = path.count == 1 ? node.children.remove(at: path.first!) : remove(&node.children[path.first!], path.dropFirst())
        node.size -= gone.size
        node.items -= gone.items
        node.count -= gone.count
        return gone
    }

    private static func replace(_ node: inout Node, _ path: ArraySlice<Int>, _ new: Node) {
        if path.count == 1 { node.children[path.first!] = new } else { replace(&node.children[path.first!], path.dropFirst(), new) }
    }
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
