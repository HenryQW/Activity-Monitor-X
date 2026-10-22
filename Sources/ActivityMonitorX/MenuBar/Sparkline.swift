import SwiftUI

/// A line of 0 to 100 % CPU values, oldest first, on a fixed 60 point axis: a short history starts at the right.
struct CPUSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(MenuBarReadout.historyLength - 1)
        for (i, v) in values.enumerated() {
            let x = rect.maxX - step * CGFloat(values.count - 1 - i)
            let point = CGPoint(x: x, y: rect.maxY - rect.height * CGFloat(min(max(v, 0), 100) / 100))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
