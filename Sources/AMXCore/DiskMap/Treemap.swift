// MIT License. See Packaging/Credits.html.
import CoreGraphics

/// The squarified treemap of Bruls, Huizing and van Wijk: items are laid out in rows along the shorter side of
/// the remaining space, and a row takes the next item only while that does not worsen its worst aspect ratio.
public enum Treemap {
    public struct Cell: Sendable {
        public let path: [Int]
        public let rect: CGRect
        public let depth: Int
        public let name: String
        public let size: UInt64
        public let kind: DiskTree.Node.Kind
    }

    /// One rect per weight, in input order, tiling `rect`. Weights descending give the best shapes; a zero
    /// weight gets an empty rect.
    public static func squarify(_ weights: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: CGRect(origin: rect.origin, size: .zero), count: weights.count)
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let areas = weights.map { max(0, $0) * rect.width * rect.height / total }
        var remaining = rect
        var start = 0
        while start < areas.count {
            guard areas[start] > 0 else { start += 1; continue }
            let side = min(remaining.width, remaining.height)
            var end = start + 1
            var rowArea = areas[start], rowMin = areas[start], rowMax = areas[start]
            var best = worst(rowMin, rowMax, rowArea, side)
            while end < areas.count, areas[end] > 0 {
                let ratio = worst(min(rowMin, areas[end]), max(rowMax, areas[end]), rowArea + areas[end], side)
                guard ratio <= best else { break }
                rowArea += areas[end]
                rowMin = min(rowMin, areas[end])
                rowMax = max(rowMax, areas[end])
                best = ratio
                end += 1
            }
            if remaining.width >= remaining.height {
                // A column down the left edge; the last cell takes what is left, so rounding leaves no gap.
                let width = min(remaining.width, rowArea / remaining.height)
                var y = remaining.minY
                for i in start..<end {
                    let height = i == end - 1 ? remaining.maxY - y : areas[i] / width
                    result[i] = CGRect(x: remaining.minX, y: y, width: width, height: max(0, height))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // A row along the top edge.
                let height = min(remaining.height, rowArea / remaining.width)
                var x = remaining.minX
                for i in start..<end {
                    let width = i == end - 1 ? remaining.maxX - x : areas[i] / height
                    result[i] = CGRect(x: x, y: remaining.minY, width: max(0, width), height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
            start = end
        }
        return result
    }

    /// The worst aspect ratio in a row of total area `rowArea` along a side of length `side`.
    private static func worst(_ rowMin: Double, _ rowMax: Double, _ rowArea: Double, _ side: Double) -> Double {
        max(side * side * rowMax / (rowArea * rowArea), rowArea * rowArea / (side * side * rowMin))
    }

    /// Cells for `node`'s children in `rect`, down to `depth` levels. A folder's children go inside its rect,
    /// inset; a cell under `minArea` is not emitted (its area stays with its parent).
    public static func cells(_ node: DiskTree.Node, in rect: CGRect, depth: Int = 3, minArea: Double = 12,
                             inset: Double = 1) -> [Cell] {
        var out: [Cell] = []
        func place(_ node: DiskTree.Node, _ path: [Int], _ rect: CGRect, _ level: Int) {
            let rects = squarify(node.children.map { Double($0.size) }, in: rect)
            for (i, child) in node.children.enumerated() where rects[i].width * rects[i].height >= minArea {
                out.append(Cell(path: path + [i], rect: rects[i], depth: level, name: child.name, size: child.size,
                                kind: child.kind))
                if level < depth, child.kind == .folder {
                    place(child, path + [i], rects[i].insetBy(dx: inset, dy: inset), level + 1)
                }
            }
        }
        place(node, [], rect, 1)
        return out
    }
}
