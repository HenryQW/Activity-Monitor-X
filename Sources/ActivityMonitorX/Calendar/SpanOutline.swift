import SwiftUI

/// The outline of a selection: the outer edges of its cells, joined into one path, not a border per cell. A span that falls
/// into parts which do not touch (a short span over a row end) leaves the sides at the break open, so the parts read as one
/// span that continues.
enum SpanOutline {
    enum Side { case top, bottom, leading, trailing }

    struct Cell {
        let rect: CGRect
        var open: Set<Side> = []
    }

    private struct Point: Hashable { let x: Int, y: Int }
    private struct Segment: Hashable { let a: Point, b: Point }

    /// The edges that no two cells share, from rects in half points, with whether a cell left that side open.
    private static func edges(_ cells: [Cell]) -> [(segment: Segment, open: Bool)] {
        func point(_ x: CGFloat, _ y: CGFloat) -> Point { Point(x: Int((x * 2).rounded()), y: Int((y * 2).rounded())) }
        var edges: [Segment: Bool] = [:]
        for cell in cells {
            let r = cell.rect
            let sides: [(Side, Segment)] = [
                (.top, Segment(a: point(r.minX, r.minY), b: point(r.maxX, r.minY))),
                (.bottom, Segment(a: point(r.minX, r.maxY), b: point(r.maxX, r.maxY))),
                (.leading, Segment(a: point(r.minX, r.minY), b: point(r.minX, r.maxY))),
                (.trailing, Segment(a: point(r.maxX, r.minY), b: point(r.maxX, r.maxY))),
            ]
            for (side, segment) in sides {
                // A shared edge is inside the span.
                if edges[segment] != nil { edges[segment] = nil } else { edges[segment] = cell.open.contains(side) }
            }
        }
        return edges.map { (segment: $0.key, open: $0.value) }
    }

    /// Joins the segments end to end; a path starts at an odd end first, so an open outline is one path.
    private static func chain(_ segments: [Segment]) -> [[Point]] {
        var at: [Point: [Int]] = [:]
        for (i, s) in segments.enumerated() {
            at[s.a, default: []].append(i)
            at[s.b, default: []].append(i)
        }
        var used = Set<Int>(), paths: [[Point]] = []
        let starts = at.keys.sorted { (at[$0]!.count % 2, $1.x, $1.y) > (at[$1]!.count % 2, $0.x, $0.y) }
        for start in starts {
            var point = start, points: [Point] = []
            while let i = at[point]!.first(where: { !used.contains($0) }) {
                if points.isEmpty { points.append(point) }
                used.insert(i)
                point = segments[i].a == point ? segments[i].b : segments[i].a
                points.append(point)
            }
            if !points.isEmpty { paths.append(points) }
        }
        return paths
    }

    static func path(_ cells: [Cell]) -> Path {
        let all = edges(cells)
        var paths = chain(all.map(\.segment))
        if paths.count > 1 { paths = chain(all.filter { !$0.open }.map(\.segment)) }
        var path = Path()
        for points in paths {
            path.move(to: CGPoint(x: Double(points[0].x) / 2, y: Double(points[0].y) / 2))
            for p in points.dropFirst() { path.addLine(to: CGPoint(x: Double(p.x) / 2, y: Double(p.y) / 2)) }
            if points.first == points.last { path.closeSubpath() }
        }
        return path
    }

    static func fill(_ cells: [Cell]) -> Path {
        var path = Path()
        for cell in cells { path.addRect(cell.rect) }
        return path
    }
}
