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

/// One line, no axes, from 0 to `top`. Past `threshold` (an alert rule's level) the line turns warning yellow above a
/// thin dashed line at the level, and the warning triangle shows, so colour is never the only cue (COL-1).
struct Sparkline: View {
    let values: [Double]
    let color: Color
    let top: Double
    var threshold: Double?

    var body: some View {
        let line = SparklineShape(values: values, top: top, slots: values.count)
        let style = StrokeStyle(lineWidth: 1.5, lineJoin: .round)
        // A level at or over `top` has no value above it to draw.
        let level = threshold.flatMap { $0 < top ? $0 / top : nil }
        HStack(spacing: 2) {
            ZStack {
                line.stroke(color, style: style)
                if let level {
                    LevelShape(level: level, line: true).stroke(.tertiary, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    line.stroke(.yellow, style: style).mask(LevelShape(level: level))
                }
            }
            .frame(height: 18)
            .accessibilityHidden(true)
            // Kept, hidden, under the level: every row with a rule has the same line width.
            if let threshold {
                let over = values.contains { $0 >= threshold }
                SeverityIcon(severity: 1).imageScale(.small).opacity(over ? 1 : 0).accessibilityHidden(!over)
            }
        }
    }
}

/// The part of the rect above `level` (0 to 1 of its height, from the bottom), or the line at it.
private struct LevelShape: Shape {
    let level: Double
    var line = false

    func path(in rect: CGRect) -> Path {
        let y = rect.maxY - rect.height * level
        if !line { return Path(CGRect(x: rect.minX - 2, y: rect.minY - 2, width: rect.width + 4, height: y - rect.minY + 2)) }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}
