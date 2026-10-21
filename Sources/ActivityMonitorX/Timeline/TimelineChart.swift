import AMXCore
import Charts
import SwiftUI

/// Stacked areas for the top apps + Other; hover shows a value bubble, drag selects a span.
struct TimelineChart: View {
    private let points: [SeriesPoint]
    private let colors: [AppKey: Color]
    private let bucket: Double
    private let metric: Metric
    private let events: [EventMark]
    private let span: ClosedRange<Date>?
    /// nil when the range has no span (Live).
    private let commitSpan: ((ClosedRange<Date>) -> Void)?
    private let series: [Series]
    private let labels: [AppKey?: String]
    private let byBucket: [Double: [SeriesPoint]]
    private let totals: [Double: Double]
    private let top: Double

    private let _hover = State<Date?>(initialValue: nil)
    /// The span while dragging; committed to the model once the drag rests, so ranking runs once per drag.
    private let _drag = State<ClosedRange<Date>?>(initialValue: nil)

    /// `points` is non-empty and ordered by bucket; every bucket holds every series.
    /// `colors` holds every named app of `points`.
    init(points: [SeriesPoint], colors: [AppKey: Color], bucket: Double, metric: Metric, events: [EventMark],
         span: ClosedRange<Date>?, commitSpan: ((ClosedRange<Date>) -> Void)?) {
        (self.points, self.colors, self.bucket, self.metric, self.events, self.span, self.commitSpan)
            = (points, colors, bucket, metric, events, span, commitSpan)
        series = Self.series(points, colors: colors)
        labels = Dictionary(uniqueKeysWithValues: series.map { ($0.app, $0.label) })
        byBucket = Dictionary(grouping: points, by: \.bucket)
        totals = byBucket.mapValues { $0.reduce(0) { $0 + $1.value } }
        let peak = totals.values.max() ?? 0
        // 20 % headroom keeps the stack clear of the event lane at the top of the plot.
        top = (peak > 0 ? peak : 1) * 1.2
    }

    var body: some View {
        let shownSpan = _drag.wrappedValue ?? span
        Chart {
            ForEach(points.indices, id: \.self) { i in
                AreaMark(x: .value("Time", Self.date(points[i].bucket)),
                         y: .value(metric.label, points[i].value),
                         stacking: .standard)
                    .foregroundStyle(by: .value("App", labels[points[i].app]!))
            }
            if let shownSpan {
                RectangleMark(xStart: .value("Start", shownSpan.lowerBound), xEnd: .value("End", shownSpan.upperBound))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
            }
            if let hover = _hover.wrappedValue,
               let b = byBucket.keys.filter({ $0 <= hover.timeIntervalSince1970 }).max() {
                RuleMark(x: .value("Time", hover))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        bubble(bucket: b)
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.label), range: series.map(\.color))
        .chartXScale(domain: Self.date(points.first!.bucket)...Self.date(points.last!.bucket + bucket))
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(metric.axisLabel(v)) }
                }
            }
        }
        // One line: names truncate instead of wrapping into a second row.
        .chartLegend(position: .bottom, alignment: .leading) {
            HStack(spacing: 12) {
                ForEach(series.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(series[i].color).frame(width: 8, height: 8)
                        Text(series[i].label).lineLimit(1)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Color.secondary)
        }
        .chartXSelection(value: _hover.projectedValue)
        .chartXSelection(range: dragBinding)
        .chartOverlay { proxy in EventLane(events: events, proxy: proxy) }
        // Charts reports no drag end on macOS: commit once the range has not changed for 250 ms.
        .task(id: _drag.wrappedValue) {
            guard let drag = _drag.wrappedValue, let commitSpan,
                  (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            commitSpan(drag)
            _drag.wrappedValue = nil
        }
    }

    private var dragBinding: Binding<ClosedRange<Date>?> {
        Binding(
            get: { _drag.wrappedValue ?? span },
            set: { range in
                // A click reports an empty or nil range; only a drag of at least one bucket counts.
                guard commitSpan != nil, let range, range.upperBound.timeIntervalSince(range.lowerBound) >= bucket else { return }
                _drag.wrappedValue = range
            })
    }

    private func bubble(bucket b: Double) -> some View {
        let rows = byBucket[b]!.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(Self.date(b).formatted(timeFormat)) · \(metric.format(totals[b]!))")
                .fontWeight(.semibold)
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(rows[i].app.map { colors[$0]! } ?? AppPalette.other)
                        .frame(width: 8, height: 8)
                    Text(labels[rows[i].app]!)
                    Spacer(minLength: 8)
                    Text(metric.format(rows[i].value)).monospacedDigit()
                }
            }
        }
        .font(.caption)
        .fixedSize()
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private var timeFormat: Date.FormatStyle {
        if bucket >= 3600 { return .dateTime.month(.abbreviated).day().hour().minute() }
        return bucket < 60 ? .dateTime.hour().minute().second() : .dateTime.hour().minute()
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private struct Series {
        let app: AppKey?
        let label: String
        let color: Color
    }

    /// Legend labels are display names, made unique so two apps sharing a name stay two series.
    private static func series(_ points: [SeriesPoint], colors: [AppKey: Color]) -> [Series] {
        var used = ["Other": 1]
        return points.prefix { $0.bucket == points[0].bucket }.map { point in
            guard let app = point.app else { return Series(app: nil, label: "Other", color: AppPalette.other) }
            let n = (used[app.name] ?? 0) + 1
            used[app.name] = n
            return Series(app: app, label: n == 1 ? app.name : "\(app.name) (\(n))", color: colors[app]!)
        }
    }
}
