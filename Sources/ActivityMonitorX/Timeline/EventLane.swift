import AMXCore
import Charts
import SwiftUI

/// Pressure ▲, thermal ◆ and alert ● markers on the chart's x scale, in the headroom strip at the top of the plot. Events closer
/// than 12 pt share one marker with a count; shape and colour come from the most severe one: yellow warns, red is
/// critical (the app palette uses neither); in light mode a warning has a dark outline, as yellow on white is under 3:1.
/// A hover highlights the marker, shades its span and lists its events, info events included, in a popover; a click
/// keeps the same popover open and selects their span.
struct EventLane: View {
    let events: [EventMark]
    let proxy: ChartProxy
    /// The chart bucket: the span a marker selects is at least one bucket, up to its last event.
    let bucket: Double
    /// The range the data on screen was loaded for, by its bucket: while Live starts, the earlier range still shows.
    private var shownRange: HistoryRange { bucket >= HistoryRange.day.chartBucket ? .day : .hour }
    /// The chart's first bucket: a selected span starts no earlier.
    let start: Double
    /// Selects a span of the chart; nil without spans (Live).
    let select: ((ClosedRange<Date>) -> Void)?
    /// The chart's largest app in the bucket that holds a time: read from the stack, not the tracks, so a hover is cheap.
    let topApp: (Double) -> String?
    /// The lead event's ts of the cluster under the pointer; the chart hides its value bubble meanwhile.
    let hovered: Binding<Double?>
    @Environment(\.colorScheme) private var colorScheme
    /// The lead event's ts of the cluster whose popover is open, stable while a reload shifts the cluster indices, and
    /// whether a click opened it: a hover's popover closes when the pointer leaves the marker.
    private let _open = State<(ts: Double, click: Bool)?>(initialValue: nil)

    /// The chart legend's key to the marker shapes.
    static let legend = [(symbol: "triangle.fill", name: "Pressure"), (symbol: "diamond.fill", name: "Thermal"),
                         (symbol: "circle.fill", name: "Alert")]

    var body: some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                let clusters = EventClusters.clusters(events.compactMap { event in
                    proxy.position(forX: Date(timeIntervalSince1970: event.ts)).flatMap { (0...plot.width).contains($0) ? (x: $0, event: event) : nil }
                }, gap: 12)
                let active = clusters.first { $0.lead.ts == hovered.wrappedValue }
                // A reload can drop the hovered or open cluster: the chart's value bubble must not stay hidden, and a
                // later click must not find a popover open without its marker.
                Color.clear.onChange(of: clusters.map(\.lead.ts)) { _, leads in
                    if let ts = hovered.wrappedValue, !leads.contains(ts) { hovered.wrappedValue = nil }
                    if let ts = _open.wrappedValue?.ts, !leads.contains(ts) { _open.wrappedValue = nil }
                }
                if let active, let lo = proxy.position(forX: span(active).lowerBound), let hi = proxy.position(forX: span(active).upperBound) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: max(hi - lo, 1), height: plot.height)
                        .position(x: plot.minX + (lo + hi) / 2, y: plot.midY)
                        .allowsHitTesting(false)
                }
                ForEach(clusters.indices, id: \.self) { i in
                    let cluster = clusters[i]
                    Button {
                        _open.wrappedValue = (cluster.lead.ts, true)
                        select?(span(cluster))
                    } label: {
                        let symbol = Self.symbol(cluster.lead.kind)
                        let warning = cluster.lead.level != 2
                        // The count sits beside the symbol, so the symbol stays on the event's x.
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(warning ? Color.yellow : .red)
                            .overlay {
                                if warning && colorScheme == .light {
                                    Image(systemName: String(symbol.dropLast(".fill".count)))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.black.opacity(0.55))
                                }
                            }
                            .overlay(alignment: .leading) {
                                if cluster.events.count > 1 {
                                    Text(String(cluster.events.count))
                                        .font(.system(size: 10, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                        .fixedSize()
                                        .offset(x: 13)
                                }
                            }
                            .padding(3)
                            .background(.primary.opacity(hovered.wrappedValue == cluster.lead.ts ? 0.15 : 0), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    // An exit clears only this marker's hover and hover popover: the next marker's enter can come first.
                    // One popover at a time: a click's popover stays until a click outside or Esc.
                    .onHover { inside in
                        let ts = cluster.lead.ts
                        if inside {
                            hovered.wrappedValue = ts
                            if _open.wrappedValue?.click != true { _open.wrappedValue = (ts, false) }
                        } else {
                            if hovered.wrappedValue == ts { hovered.wrappedValue = nil }
                            if let open = _open.wrappedValue, !open.click, open.ts == ts { _open.wrappedValue = nil }
                        }
                    }
                    // Only this marker's own dismissal closes it, not a late one after the pointer moved to the next.
                    .popover(isPresented: Binding(get: { _open.wrappedValue?.ts == cluster.lead.ts },
                                                  set: { if !$0, _open.wrappedValue?.ts == cluster.lead.ts { _open.wrappedValue = nil } }),
                             arrowEdge: .bottom) {
                        EventList(events: cluster.events)
                    }
                    .accessibilityLabel(([label(cluster)] + cluster.events.prefix(Self.listed).map(detail)).joined(separator: "; "))
                    .position(x: plot.minX + cluster.x, y: plot.minY + 8)
                }
            }
        }
    }

    /// Events in the accessibility label; the popover lists all.
    private static let listed = 8

    /// At least one bucket, ending at the last event: what led up to the events.
    private func span(_ cluster: EventCluster) -> ClosedRange<Date> {
        let first = cluster.events[0].ts, last = cluster.events[cluster.events.count - 1].ts
        return Date(timeIntervalSince1970: max(start, min(first, last - bucket)))...Date(timeIntervalSince1970: max(start, last))
    }

    /// "Memory pressure, Warning, Memory pressure warning, 1:12 AM, Top app: node".
    private func detail(_ event: EventMark) -> String {
        ([Self.kind(event.kind), Self.severity(event.level), event.message, time(event.ts)] + [app(event)].compactMap { $0 })
            .joined(separator: ", ")
    }

    private func app(_ event: EventMark) -> String? {
        event.app.map { "App: \($0.name)" } ?? topApp(event.ts).map { "Top app: \($0)" }
    }

    private func time(_ ts: Double) -> String {
        Date(timeIntervalSince1970: ts).formatted(shownRange.timeFormat)
    }

    private static func kind(_ kind: String) -> String {
        let noun = noun(kind)
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }

    private static func severity(_ level: Int?) -> String {
        switch level {
        case 2: "Critical"
        case 1: "Warning"
        default: "Info"
        }
    }

    /// "3 memory pressure events, warning, 1:12 to 1:40 AM" (the lead event's level) in the locale's interval format;
    /// from 24H up with the day, as the span bar names it.
    private func label(_ cluster: EventCluster) -> String {
        let n = cluster.events.count
        let kinds = Set(cluster.events.map(\.kind))
        let noun = kinds.count == 1 ? Self.noun(cluster.lead.kind) + " " : ""
        let first = Date(timeIntervalSince1970: cluster.events[0].ts)
        let last = Date(timeIntervalSince1970: cluster.events[n - 1].ts)
        let when = first == last
            ? time(cluster.events[0].ts)
            : (first..<last).formatted(shownRange.intervalFormat)
        return "\(n) \(noun)event\(n == 1 ? "" : "s"), \(Self.severity(cluster.lead.level).lowercased()), \(when)"
    }

    private static func noun(_ kind: String) -> String {
        switch kind {
        case EventKind.pressure: "memory pressure"
        case EventKind.thermal: "thermal"
        default: "alert"
        }
    }

    private static func symbol(_ kind: String) -> String {
        switch kind {
        case EventKind.pressure: "triangle.fill"
        case EventKind.thermal: "diamond.fill"
        default: "circle.fill"
        }
    }
}

/// "1:12 AM  Memory pressure warning": the day once on top when all events share it, else on each line.
private struct EventList: View {
    let events: [EventMark]

    var body: some View {
        let dates = events.map { Date(timeIntervalSince1970: $0.ts) }
        let oneDay = Set(dates.map { Calendar.current.startOfDay(for: $0) }).count == 1
        // A long cluster (90D) scrolls instead of running off the screen.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if oneDay {
                    Text(dates[0].formatted(date: .abbreviated, time: .omitted)).font(.headline)
                }
                ForEach(events.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        Text(dates[i].formatted(oneDay ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(events[i].message)
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 360)
    }
}
