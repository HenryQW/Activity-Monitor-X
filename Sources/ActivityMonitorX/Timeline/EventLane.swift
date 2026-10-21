import AMXCore
import Charts
import SwiftUI

/// Pressure ▲ and thermal ◆ markers on the chart's x scale, in the headroom strip at the top of the plot. Events closer
/// than 12 pt share one marker with a count; shape and colour come from the most severe one: yellow warns, red is
/// critical (the app palette uses neither). Info events show only in a marker's help list.
struct EventLane: View {
    let events: [EventMark]
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                let clusters = EventClusters.clusters(events.compactMap { event in
                    proxy.position(forX: Date(timeIntervalSince1970: event.ts)).flatMap { (0...plot.width).contains($0) ? (x: $0, event: event) : nil }
                }, gap: 12)
                ForEach(clusters.indices, id: \.self) { i in
                    let cluster = clusters[i]
                    let list = cluster.events.map { "\(Date(timeIntervalSince1970: $0.ts).formatted(.dateTime.month(.abbreviated).day().hour().minute()))  \($0.message)" }
                        .joined(separator: "\n")
                    // The count sits beside the symbol, so the symbol stays on the event's x.
                    Image(systemName: cluster.lead.kind == "pressure" ? "triangle.fill" : "diamond.fill")
                        .font(.system(size: 9))
                        .overlay(alignment: .leading) {
                            if cluster.events.count > 1 {
                                Text(String(cluster.events.count)).font(.system(size: 8, weight: .semibold)).fixedSize().offset(x: 10)
                            }
                        }
                        .foregroundStyle(cluster.lead.level == 2 ? Color.red : .yellow)
                        .help(list)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(list)
                        .position(x: plot.minX + cluster.x, y: plot.minY + 8)
                }
            }
        }
    }
}
