import Testing
@testable import AMXCore

@Suite struct DiskTreeEditTests {
    private static func leaf(_ name: String, _ size: UInt64) -> DiskTree.Node {
        .init(name: name, kind: .file, size: size, items: 1, children: [], count: 1)
    }

    private static func tree() -> DiskTree {
        let dir = DiskTree.Node(name: "d", kind: .folder, size: 30, items: 3, children: [leaf("a", 20), leaf("b", 10)], count: 3)
        let root = DiskTree.Node(name: "/r", kind: .folder, size: 40, items: 5, children: [dir, leaf("c", 10)], count: 5)
        return DiskTree(rootPath: "/r", root: root, refused: [], refusedCount: 0, partial: false, simplified: false)
    }

    @Test func removeTakesSizeOffEveryFolderAbove() {
        var tree = Self.tree()
        tree.remove(at: [0, 0])
        #expect(tree[[0]].children.map(\.name) == ["b"])
        #expect([tree[[0]].size, tree.root.size] == [10, 20])
        #expect([tree[[0]].items, tree.root.items, tree[[0]].count, tree.root.count] == [2, 4, 2, 4])
    }

    @Test func renameKeepsOrderAndSizes() {
        var tree = Self.tree()
        tree.rename(at: [0, 1], to: "z")
        #expect(tree[[0]].children.map(\.name) == ["a", "z"])
        #expect(tree.root.size == 40)
    }
}
