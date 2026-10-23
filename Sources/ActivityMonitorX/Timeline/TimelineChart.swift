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
    /// Live draws smooth curves (D27). A 1 s slide of the plot to each new second was measured at about 20 % CPU (the
    /// plot layer is drawn again every display frame), so Live still steps once a second.
    private let live: Bool
    private let metric: Metric
    private let events: [EventMark]
    private let span: ClosedRange<Date>?
    /// nil when the range has no span (Live).
    private let commitSpan: ((ClosedRange<Date>) -> Void)?
    /// The largest processes inside Other for the bucket starting at the given time.
    private let otherProcesses: (Double) -> [(name: String, value: Double)]
    /// Reports the app key ("" for Other) of the legend item under the pointer (true) and leaving it (false).
    private let hover: (String, Bool) -> Void
    /// The hovered app's own line over the stack, nil unless that app has no band.
    private let line: [Mark]?
    private let series: [Series]
    private let labels: [AppKey?: String]
    private let top: Double

    private let _hover = State<Date?>(initialValue: nil)
    /// The span while dragging; committed to the model once the drag rests, so ranking runs once per drag.
    private let _drag = State<ClosedRange<Date>?>(initialValue: nil)
    /// The event marker under the pointer (its lead ts): its popover replaces the value bubble.
    private let _event = State<Double?>(initialValue: nil)

    /// `points` is non-empty and ordered by bucket; every bucket holds every series.
    /// `colors` holds every named app of `points`. With `highlighted` (search, or the hovered app key, "" for Other),
    /// the other series are dimmed to the `dim` opacity.
    /// `line` is the series of a hovered app without a band: it is drawn over the dimmed stack in `AppPalette.hover`.
    init(points: [SeriesPoint], colors: [AppKey: Color], bucket: Double, live: Bool = false, metric: Metric, events: [EventMark],
         highlighted: Set<String>? = nil, dim: Double = 0.25, line: [SeriesPoint]? = nil, span: ClosedRange<Date>?, commitSpan: ((ClosedRange<Date>) -> Void)?,
         otherProcesses: @escaping (Double) -> [(name: String, value: Double)], hover: @escaping (String, Bool) -> Void) {
        (self.points, self.colors, self.bucket, self.live, self.metric, self.events, self.span, self.commitSpan, self.otherProcesses)
            = (points, colors, bucket, live, metric, events, span, commitSpan, otherProcesses)
        self.hover = hover
        series = Self.series(points, colors: colors, highlighted: highlighted, dim: dim)
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
        self.line = line.map { AppSeries.closed($0, bucket: bucket).map {
            Mark(date: Self.date($0.bucket), low: 0, high: $0.value, label: "", value: $0.value, metric: metric) } }
        // A bucket's last band ends at its total.
        let peak = marks.lazy.map(\.high).max() ?? 0
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
                // One band's top and the next band's bottom are the same values, so the curves still meet.
                .interpolationMethod(live ? .monotone : .linear)
            if let line {
                // In the colour scale like the bands: a plain style next to the scale traps Charts in layout. A filled area
                // with a line on top, so the app stands out over the dimmed stack.
                AreaPlot(line, x: .value("Time", \.date), yStart: .value(metric.label, \.low), yEnd: .value(metric.label, \.high),
                         series: .value("App", Self.hoverLabel))
                    .foregroundStyle(by: .value("App", Self.hoverLabel))
                    .opacity(0.35)
                    .interpolationMethod(live ? .monotone : .linear)
                LinePlot(line, x: .value("Time", \.date), y: .value(metric.label, \.value), series: .value("App", Self.hoverLabel))
                    .foregroundStyle(by: .value("App", Self.hoverLabel))
                    .interpolationMethod(live ? .monotone : .linear)
            }
            if let shownSpan {
                RectangleMark(xStart: .value("Start", shownSpan.lowerBound), xEnd: .value("End", shownSpan.upperBound))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
            }
        }
        // The hover entry stays in the scale while no app is hovered: a domain that loses a value Charts still draws traps.
        .chartForegroundStyleScale(domain: series.map(\.label) + [Self.hoverLabel], range: series.map(\.color) + [AppPalette.hover])
        .chartXScale(domain: Self.date(points.first!.bucket)...Self.date(points.last!.bucket + bucket))
        .chartYScale(domain: 0...top)
        // Labels centred on their ticks: a label leading from a tick near the end was cut off ("4…"); centred, it
        // needs only half its width past the plot, inside the trailing y-axis column.
        .chartXAxis {
            // Solid, faint gridlines: dashed ones read as a selection or a threshold.
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(metric.axisLabel(v)) }
                }
            }
        }
        // One line: names truncate instead of wrapping into a second row. The top apps are ranked by the busiest
        // buckets (D18), so the title says so: the table below keeps its own sort.
        .chartLegend(position: .bottom, alignment: .leading) {
            HStack(spacing: 12) {
                if series.count > 1 { Text("Top during peaks").fontWeight(.medium).lineLimit(1) }
                ForEach(series.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Circle().fill(series[i].color).frame(width: 8, height: 8)
                        Text(series[i].label).lineLimit(1)
                    }
                    .onHover { hover(series[i].app?.key ?? "", $0) }
                    .onDisappear { hover(series[i].app?.key ?? "", false) }
                }
                // The lane shows warning and critical events only.
                if events.contains(where: { ($0.level ?? 0) >= 1 }) {
                    Spacer(minLength: 12)
                    ForEach(EventLane.legend, id: \.symbol) { item in
                        Label(item.name, systemImage: item.symbol).imageScale(.small).lineLimit(1)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Color.secondary)
        }
        .chartXSelection(value: _hover.projectedValue)
        .chartXSelection(range: dragBinding)
        .chartOverlay { proxy in
            EventLane(events: events, proxy: proxy, bucket: bucket, start: points[0].bucket, select: commitSpan, topApp: topApp,
                      hovered: _event.projectedValue)
            // Only this layer reads the hover, so a mouse move does not rebuild the areas.
            if _event.wrappedValue == nil {
                HoverLayer(hover: _hover.projectedValue, proxy: proxy) { date in
                    bucketPoints(at: date.timeIntervalSince1970).map(bubble)
                }
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

    private func bubble(_ points: ArraySlice<SeriesPoint>) -> some View {
        let zero = metric.format(0)
        let b = points.first!.bucket
        let rows = AppSeries.bubbleRows(Array(points)) { metric.format($0) == zero }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(Self.date(b).formatted(.hover(bucket: bucket))) · \(metric.format(points.reduce(0) { $0 + $1.value }))")
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
            // Other's largest processes, under its row.
            if rows.last?.app == nil {
                let inOther = otherProcesses(b).filter { metric.format($0.value) != zero }
                ForEach(inOther.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        Text(inOther[i].name).padding(.leading, 13)
                        Spacer(minLength: 8)
                        Text(metric.format(inOther[i].value)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .hoverBubble()
    }

    /// The hover line's key in the colour scale; never a legend label (the legend lists `series` only).
    private static let hoverLabel = "\u{1}hover"

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    /// The points of the bucket that holds `ts`: the last bucket that starts at or before it. Every bucket holds every
    /// series, so bucket k is `series.count` points from k × `series.count`.
    private func bucketPoints(at ts: Double) -> ArraySlice<SeriesPoint>? {
        let n = series.count
        return (0..<points.count / n).last { points[$0 * n].bucket <= ts }.map { points[$0 * n..<($0 + 1) * n] }
    }

    /// The largest named app in the bucket that holds `ts`.
    private func topApp(at ts: Double) -> String? {
        bucketPoints(at: ts)?.filter { $0.app != nil && $0.value > 0 }.max { $0.value < $1.value }.map { labels[$0.app]! }
    }

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
    private static func series(_ points: [SeriesPoint], colors: [AppKey: Color], highlighted: Set<String>?, dim: Double) -> [Series] {
        let first = points.prefix { $0.bucket == points[0].bucket }
        return zip(first, AppSeries.labels(first.map { $0.app?.name })).map { point, label in
            let color = point.app.map { colors[$0]! } ?? AppPalette.other
            // Other never matches a search; it matches a hover on its legend item ("").
            let shown = highlighted.map { $0.contains(point.app?.key ?? "") } ?? true ? color : color.opacity(dim)
            return Series(app: point.app, label: label, color: shown)
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

extension HistoryRange {
    /// A time in the range: from 24H up with the day, as the range can cross midnight.
    var timeFormat: Date.FormatStyle {
        seconds >= Self.day.seconds ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute()
    }

    /// Two times in the range, with the day as in `timeFormat`.
    var intervalFormat: Date.IntervalFormatStyle {
        seconds >= Self.day.seconds ? .interval.month(.abbreviated).day().hour().minute() : .interval.hour().minute()
    }
}

extension View {
    /// The look of a chart's hover bubble: a material, not glass, so the bands behind it do not refract through the text.
    func hoverBubble() -> some View {
        font(.caption).fixedSize().padding(8).background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}

/// The hover rule and value bubble over the plot; the bubble sits right of the rule and stays inside the plot. It takes
/// no pointer events: a popover that follows the pointer flickered when the pointer ran into it (D24, D58). Only this
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
