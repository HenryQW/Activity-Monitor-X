import SwiftUI

/// A line of values from 0 to `top`, oldest first, on a fixed axis of `slots` points: a short history starts at the right.
/// A plain path, so a table of them redraws far cheaper than one chart per row.
struct SparklineShape: Shape {
    let values: [Double]
    var top: Double = 100
    var slots: Int = MenuBarReadout.historyLength

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(max(slots, values.count, 2) - 1)
        let scale = top > 0 ? top : 1
        for (i, v) in values.enumerated() {
            let x = rect.maxX - step * CGFloat(values.count - 1 - i)
            let point = CGPoint(x: x, y: rect.maxY - rect.height * CGFloat(min(max(v, 0), scale) / scale))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
