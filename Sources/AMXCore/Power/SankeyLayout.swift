import CoreGraphics

/// Node rectangles and band edges of a band diagram whose band widths are proportional to their weights.
public enum SankeyLayout {
    /// A band from the trailing edge of its source node to the leading edge of its target, with its top at `y0` and `y1`.
    public struct Band: Equatable, Sendable {
        public let x0, y0, x1, y1, thickness: Double
    }

    /// Nodes are given by column; a node is as tall as the larger of what flows in and out of it. Each column stacks its
    /// nodes in order with `gap` between them, centred; one scale serves all columns, so the fullest column fills
    /// `size.height`. Bands leave and enter nodes in link order, top first. All weights 0 give zero heights. Columns are
    /// at `xs` when given, else evenly across `size.width`.
    public static func layout(columns: [Int], links: [(from: Int, to: Int, weight: Double)], size: CGSize,
                              nodeWidth: Double, gap: Double, xs: [Double]? = nil) -> (nodes: [CGRect], bands: [Band]) {
        var inflow = [Double](repeating: 0, count: columns.count), outflow = inflow
        for link in links {
            outflow[link.from] += link.weight
            inflow[link.to] += link.weight
        }
        let weights = zip(inflow, outflow).map { max($0, $1) }
        let count = (columns.max() ?? -1) + 1
        let members = (0..<count).map { c in columns.indices.filter { columns[$0] == c } }
        let scale = members.compactMap { nodes -> Double? in
            let total = nodes.reduce(0) { $0 + weights[$1] }
            return total > 0 ? (size.height - Double(nodes.count - 1) * gap) / total : nil
        }.min().map { max(0, $0) } ?? 0
        var nodes = [CGRect](repeating: .zero, count: columns.count)
        for (c, column) in members.enumerated() {
            let x = xs?[c] ?? (count > 1 ? Double(c) * (size.width - nodeWidth) / Double(count - 1) : 0)
            var y = (size.height - column.reduce(0) { $0 + weights[$1] * scale } - Double(max(0, column.count - 1)) * gap) / 2
            for i in column {
                nodes[i] = CGRect(x: x, y: y, width: nodeWidth, height: weights[i] * scale)
                y += weights[i] * scale + gap
            }
        }
        var out = [Double](repeating: 0, count: columns.count), into = out
        let bands = links.map { link in
            let thickness = link.weight * scale
            defer { (out[link.from], into[link.to]) = (out[link.from] + thickness, into[link.to] + thickness) }
            return Band(x0: nodes[link.from].maxX, y0: nodes[link.from].minY + out[link.from],
                        x1: nodes[link.to].minX, y1: nodes[link.to].minY + into[link.to], thickness: thickness)
        }
        return (nodes, bands)
    }

    /// Column positions in `width` where the columns from `labelled` on carry labels at their right: each gap between them
    /// is `labelStep`, and the columns before share what is left equally. Where `width` is short, the labelled gaps shrink
    /// first, to keep each earlier gap `minStep` wide.
    public static func columnX(count: Int, width: Double, nodeWidth: Double, labelled: Int, labelStep: Double,
                               minStep: Double) -> [Double] {
        guard count > 1 else { return [0] }
        let span = width - nodeWidth
        let early = min(labelled, count - 1), late = count - 1 - early
        let step = late == 0 ? 0 : max(0, min(labelStep, (span - Double(early) * minStep) / Double(late)))
        let first = (span - Double(late) * step) / Double(early)
        return (0..<count).map { c in c <= early ? Double(c) * first : Double(early) * first + Double(c - early) * step }
    }

    /// Label centres moved the least from `centers` (top to bottom) so that they stay `spacing` apart inside `range`
    /// where they fit.
    public static func spread(_ centers: [Double], spacing: Double, in range: ClosedRange<Double>) -> [Double] {
        var out = centers
        for i in out.indices { out[i] = max(out[i], i == 0 ? range.lowerBound : out[i - 1] + spacing) }
        for i in out.indices.reversed() { out[i] = min(out[i], i == out.count - 1 ? range.upperBound : out[i + 1] - spacing) }
        return out
    }
}
