import AMXCore
import Charts
import SwiftUI

/// Stacked areas for the top apps + Other; hover shows a value bubble, drag selects a span.
struct TimelineChart: View {
    private let points: [SeriesPoint]
    /// `points` with the last bucket closed, as drawn: one vectorized plot, not a mark per point.
    private let marks: [Mark]
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
    /// `colors` holds every named app of `points`. With `highlighted` (search), other apps' series are dimmed.
    init(points: [SeriesPoint], colors: [AppKey: Color], bucket: Double, metric: Metric, events: [EventMark],
         highlighted: Set<String>? = nil, span: ClosedRange<Date>?, commitSpan: ((ClosedRange<Date>) -> Void)?) {
        (self.points, self.colors, self.bucket, self.metric, self.events, self.span, self.commitSpan)
            = (points, colors, bucket, metric, events, span, commitSpan)
        series = Self.series(points, colors: colors, highlighted: highlighted)
        let labels = Dictionary(uniqueKeysWithValues: series.map { ($0.app, $0.label) })
        self.labels = labels
        // Stacked here, in point order (the first series at the bottom), so Charts does not stack 1800 values again.
        var stack = (bucket: -Double.infinity, top: 0.0)
        marks = AppSeries.closed(points, bucket: bucket).map { point in
            if point.bucket != stack.bucket { stack = (point.bucket, 0) }
            let low = stack.top
            stack.top += point.value
            return Mark(date: Self.date(point.bucket), low: low, high: stack.top, label: labels[point.app]!,
                        value: point.value, metric: metric)
        }
        byBucket = Dictionary(grouping: points, by: \.bucket)
        totals = byBucket.mapValues { $0.reduce(0) { $0 + $1.value } }
        let peak = totals.values.max() ?? 0
        // 20 % headroom keeps the stack clear of the event lane at the top of the plot.
        top = (peak > 0 ? peak : 1) * 1.2
    }

    var body: some View {
        let shownSpan = _drag.wrappedValue ?? span
        Chart {
            AreaPlot(marks, x: .value("Time", \.date), yStart: .value(metric.label, \.low), yEnd: .value(metric.label, \.high),
                     series: .value("App", \.label))
                // VoiceOver and Audio Graph read each app's own value, not the stacked bounds.
                .accessibilityLabel(\.label)
                .accessibilityValue(\.valueText)
                .foregroundStyle(by: .value("App", \.label))
            if let shownSpan {
                RectangleMark(xStart: .value("Start", shownSpan.lowerBound), xEnd: .value("End", shownSpan.upperBound))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.label), range: series.map(\.color))
        .chartXScale(domain: Self.date(points.first!.bucket)...Self.date(points.last!.bucket + bucket))
        .chartYScale(domain: 0...top)
        // Labels centred on their ticks: a label leading from a tick near the end was cut off ("4…"); centred, it
        // needs only half its width past the plot, inside the trailing y-axis column.
        .chartXAxis { AxisMarks(preset: .aligned) }
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
        .chartOverlay { proxy in
            EventLane(events: events, proxy: proxy)
            // Only this layer reads the hover, so a mouse move does not rebuild the areas.
            HoverLayer(hover: _hover.projectedValue, proxy: proxy) { date in
                byBucket.keys.filter { $0 <= date.timeIntervalSince1970 }.max().map(bubble)
            }
        }
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
        let zero = metric.format(0)
        let rows = AppSeries.bubbleRows(byBucket[b]!) { metric.format($0) == zero }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(Self.date(b).formatted(.hover(bucket: bucket))) · \(metric.format(totals[b]!))")
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
        .hoverBubble()
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private struct Mark {
        let date: Date
        let low: Double
        let high: Double
        let label: String
        let value: Double
        let metric: Metric
        /// Formatted only when read.
        var valueText: String { metric.format(value) }
    }

    private struct Series {
        let app: AppKey?
        let label: String
        let color: Color
    }

    /// Legend labels are display names, made unique so two apps sharing a name stay two series.
    private static func series(_ points: [SeriesPoint], colors: [AppKey: Color], highlighted: Set<String>?) -> [Series] {
        var used = ["Other": 1]
        return points.prefix { $0.bucket == points[0].bucket }.map { point in
            let color = point.app.map { colors[$0]! } ?? AppPalette.other
            // Other never matches a search.
            let shown = highlighted.map { $0.contains(point.app?.key ?? "") } ?? true ? color : color.opacity(0.25)
            guard let app = point.app else { return Series(app: nil, label: "Other", color: shown) }
            let n = (used[app.name] ?? 0) + 1
            used[app.name] = n
            return Series(app: app, label: n == 1 ? app.name : "\(app.name) (\(n))", color: shown)
        }
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// A hover bubble's time: seconds below a minute bucket, the day from an hour bucket.
    static func hover(bucket: Double) -> Date.FormatStyle {
        if bucket >= 3600 { return .dateTime.month(.abbreviated).day().hour().minute() }
        return bucket < 60 ? .dateTime.hour().minute().second() : .dateTime.hour().minute()
    }
}

extension View {
    /// The look of a chart's hover bubble.
    func hoverBubble() -> some View {
        font(.caption).fixedSize().padding(8).glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}

/// The hover rule and value bubble over the plot; the bubble sits right of the rule and stays inside the plot. Only this
/// layer reads the hover, so a mouse move does not rebuild the chart's marks.
struct HoverLayer<Bubble: View>: View {
    let hover: Binding<Date?>
    let proxy: ChartProxy
    let bubble: (Date) -> Bubble

    var body: some View {
        GeometryReader { geo in
            if let date = hover.wrappedValue, let anchor = proxy.plotFrame, let x = proxy.position(forX: date) {
                let plot = geo[anchor]
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
                        path.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    bubble(date)
                        .alignmentGuide(.leading) { d in -min(plot.minX + x + 6, plot.maxX - d.width) }
                        .alignmentGuide(.top) { _ in -plot.minY }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
