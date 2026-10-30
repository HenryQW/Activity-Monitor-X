import AMXCore
import SwiftUI

/// One vertical line per bucket, as high as its value on the axis 0 to `top`. With CPU levels, dashed rules mark both. With
/// `severities` (the machine CPU level or the memory pressure of each bucket), a whole line is yellow or red. Colour is never the only cue (the counts and the text say it). A bucket with no data has no line.
struct ValueLines: View {
    let values: [Double?]
    let top: Double
    var status: CalendarStatus?
    /// The severity of each bucket.
    var severities: [Int?] = []
    /// The widest a line gets; narrower buckets make thinner lines.
    var lineWidth: CGFloat = 3
    /// A bucket to mark: the pointer is on it, or it is the selected one.
    var marked: Int?
    /// The buckets selected (Day and Hour): an accent tint behind each, so a bar keeps its colour.
    var selected: ClosedRange<Int>?

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty, top > 0 else { return }
            let slot = size.width / CGFloat(values.count), width = max(1, min(lineWidth, slot * 0.62))
            func y(_ value: Double) -> CGFloat { size.height - CGFloat(min(value, top) / top) * (size.height - 2) }
            func line(_ x: CGFloat, from: CGFloat, to: CGFloat, _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: from))
                path.addLine(to: CGPoint(x: x, y: to))
                context.stroke(path, with: .color(color), lineWidth: width)
            }
            if let warn = status?.warn, let critical = status?.critical {
                for level in [warn, critical] where level < top {
                    var rule = Path()
                    rule.move(to: CGPoint(x: 0, y: y(level)))
                    rule.addLine(to: CGPoint(x: size.width, y: y(level)))
                    context.stroke(rule, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                }
            }
            if let selected {
                let low = max(selected.lowerBound, 0), high = min(selected.upperBound, values.count - 1)
                if low <= high {
                    context.fill(Path(CGRect(x: CGFloat(low) * slot, y: 0, width: CGFloat(high - low + 1) * slot, height: size.height)),
                                 with: .color(.accentColor.opacity(0.25)))
                }
            }
            if let marked, values.indices.contains(marked) {
                context.fill(Path(CGRect(x: CGFloat(marked) * slot, y: 0, width: slot, height: size.height)), with: .color(.secondary.opacity(0.18)))
            }
            for (i, value) in values.enumerated() {
                guard let value else { continue }
                let x = (CGFloat(i) + 0.5) * slot
                guard value > 0 else {
                    line(x, from: size.height - 0.5, to: size.height, .secondary)
                    continue
                }
                let peak = y(value)
                let severity = severities.indices.contains(i) ? severities[i] ?? 0 : 0
                line(x, from: size.height, to: peak, ChipDiagram.status(severity))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The counts of buckets at the warning and the critical level: a glyph and a number each, nothing for zero.
struct LevelCounts: View {
    let counts: (warning: Int, critical: Int)

    var body: some View {
        HStack(spacing: Layout.gap) {
            if counts.critical > 0 { SeverityIcon(severity: 2).imageScale(.small); Text(counts.critical.formatted()) }
            if counts.warning > 0 { SeverityIcon(severity: 1).imageScale(.small); Text(counts.warning.formatted()) }
        }
        .monospacedDigit()
    }
}
