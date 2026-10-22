import CoreGraphics
import Testing
@testable import AMXCore

@Suite struct TreemapTests {
    private static let weights: [Double] = [6, 6, 4, 3, 2, 2, 1]
    private static let bounds = CGRect(x: 0, y: 0, width: 6, height: 4)

    @Test func areasAreProportional() {
        let rects = Treemap.squarify(Self.weights, in: Self.bounds)
        for (weight, rect) in zip(Self.weights, rects) {
            #expect(abs(rect.width * rect.height - weight) < 1e-9)
            #expect(Self.bounds.insetBy(dx: -1e-9, dy: -1e-9).contains(rect))
        }
    }

    @Test func rectsDoNotOverlap() {
        let rects = Treemap.squarify(Self.weights, in: Self.bounds)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height == 0)
            }
        }
    }

    @Test func zeroWeightsAreEmpty() {
        let rects = Treemap.squarify([3, 0, 1], in: Self.bounds)
        #expect(rects[1].width * rects[1].height == 0)
    }

    @Test func cellsStopAtDepthAndMinArea() {
        typealias Node = DiskTree.Node
        let gb: UInt64 = 1 << 30
        let file = Node(name: "f", kind: .file, size: gb, items: 1, children: [], count: 1)
        let deep = (1...4).reduce(file) { child, level in
            Node(name: "d\(level)", kind: .folder, size: gb, items: child.items + 1, children: [child], count: child.count + 1)
        }
        let tiny = Node(name: "tiny", kind: .file, size: 1, items: 1, children: [], count: 1)
        let root = Node(name: "/", kind: .folder, size: 2 * gb + 1, items: deep.items + 3,
                        children: [deep, file, tiny], count: deep.count + 3)
        let cells = Treemap.cells(root, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(cells.map(\.depth).max() == 3)
        #expect(!cells.contains { $0.name == "tiny" })
    }
}
