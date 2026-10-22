import AMXCore
import Charts
import SwiftUI

/// Pressure ▲, thermal ◆ and alert ● markers on the chart's x scale, in the headroom strip at the top of the plot. Events closer
/// than 12 pt share one marker with a count; shape and colour come from the most severe one: yellow warns, red is
/// critical (the app palette uses neither). A click lists the marker's events, info events included, in a popover.
struct EventLane: View {
    let events: [EventMark]
    let proxy: ChartProxy
    /// The lead event's ts of the cluster whose popover is open: stable while a reload shifts the cluster indices.
    private let _open = State<Double?>(initialValue: nil)

    var body: some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                let clusters = EventClusters.clusters(events.compactMap { event in
                    proxy.position(forX: Date(timeIntervalSince1970: event.ts)).flatMap { (0...plot.width).contains($0) ? (x: $0, event: event) : nil }
                }, gap: 12)
                ForEach(clusters.indices, id: \.self) { i in
                    let cluster = clusters[i]
                    Button { _open.wrappedValue = cluster.lead.ts } label: {
                        // The count sits beside the symbol, so the symbol stays on the event's x.
                        Image(systemName: Self.symbol(cluster.lead.kind))
                            .font(.system(size: 10))
                            .foregroundStyle(cluster.lead.level == 2 ? Color.red : .yellow)
                            .overlay(alignment: .leading) {
                                if cluster.events.count > 1 {
                                    Text(String(cluster.events.count))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                        .fixedSize()
                                        .offset(x: 12)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { _open.wrappedValue == cluster.lead.ts },
                                                  set: { if !$0 { _open.wrappedValue = nil } }),
                             arrowEdge: .bottom) {
                        EventList(events: cluster.events)
                    }
                    .accessibilityLabel(cluster.events.map(\.message).joined(separator: ", "))
                    .position(x: plot.minX + cluster.x, y: plot.minY + 8)
                }
            }
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
