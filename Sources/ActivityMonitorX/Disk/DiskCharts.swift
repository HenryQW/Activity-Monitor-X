import AMXCore
import Charts
import SwiftUI

/// One value per time and series, as the Disk charts draw it.
struct DiskPoint {
    let date: Date
    let series: String
    let value: Double
    /// Lines break between segments: a bucket without a value, or a time without a record (sleep), is a gap, never 0.
    var segment = 0
    /// The line the point is on: its series and segment.
    var line: String { "\(series) \(segment)" }
}

/// Lines over time with a trailing Y axis; hover shows a rule and the values at that time (`HoverLayer`).
struct DiskChart: View {
    let title: String
    /// Ordered by date.
    let points: [DiskPoint]
    /// Seconds per point: the hover time shows seconds below a minute and the day from an hour.
    let bucket: Double
    let format: (Double) -> String
    /// The X domain: the screen's range, the same for every chart.
    let xDomain: ClosedRange<Date>
    /// Fixed Y domain; nil scales to the data.
    var yDomain: ClosedRange<Double>? = nil
    /// A horizontal rule with its label (the startup volume's capacity on the Free chart).
    var rule: (value: Double, label: String)? = nil

    private let _hover = State<Date?>(initialValue: nil)

    /// Series names in first-seen order: the first takes the accent colour, a second is neutral.
    private var series: [String] {
        var seen: [String] = []
        for p in points where !seen.contains(p.series) { seen.append(p.series) }
        return seen
    }

    /// The values at the latest time at or before `date`.
    private func values(at date: Date) -> [DiskPoint] {
        guard let at = points.last(where: { $0.date <= date })?.date else { return [] }
        return points.filter { $0.date == at }
    }

    var body: some View {
        let names = series
        let latest = points.last.map { values(at: $0.date) } ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let rule { Text(rule.label).font(.caption).foregroundStyle(.secondary) }
            }
            if points.isEmpty {
                Text("No data in this range.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    // One vectorized plot, not a mark per point.
                    LinePlot(points, x: .value("Time", \.date), y: .value(title, \.value), series: .value("Segment", \.line))
                        .accessibilityLabel(\.series)
                        .foregroundStyle(by: .value("Series", \.series))
                    if let rule {
                        RuleMark(y: .value(rule.label, rule.value))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: [Color.accentColor, Color.secondary].prefix(names.count).map { $0 })
                .chartLegend(position: .top, alignment: .trailing) {
                    if names.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(names.indices, id: \.self) { i in
                                Label(names[i], systemImage: "circle.fill").foregroundStyle(i == 0 ? Color.accentColor : Color.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: AppTime.axisFormat(seconds: xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(format(v)).frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                }
                .modifier(YDomain(domain: yDomain))
                .chartXSelection(value: _hover.projectedValue)
                .chartOverlay { proxy in
                    HoverLayer(hover: _hover.projectedValue, proxy: proxy) { date in
                        values(at: date).first.map { bubble(at: $0.date) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
                .accessibilityValue(latest.map { "\($0.series) \(format($0.value))" }.joined(separator: ", "))
            }
        }
        .frame(height: 180)
    }

    private func bubble(at date: Date) -> some View {
        let rows = values(at: date)
        return PreviewCard(size: .compact, title: date.formatted(.hover(bucket: bucket)),
                           sections: [.init(rows: rows.map { .init(label: $0.series, value: format($0.value)) })])
    }
}

/// `chartYScale(domain:)` only when the domain is fixed, so other charts keep the automatic scale.
private struct YDomain: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}
