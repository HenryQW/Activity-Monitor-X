import AMXCore
import Charts
import SwiftUI

/// Pressure ▲ and thermal ◆ markers on the chart's x scale, in the headroom strip at the top of the plot.
struct EventLane: View {
    let events: [EventMark]
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                ForEach(events.indices, id: \.self) { i in
                    let event = events[i]
                    if case let (symbol, color)? = Self.style(event.kind),
                       let x = proxy.position(forX: Date(timeIntervalSince1970: event.ts)), (0...plot.width).contains(x) {
                        Image(systemName: symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(color)
                            .help(event.message)
                            .accessibilityLabel(event.message)
                            .position(x: plot.minX + x, y: plot.minY + 8)
                    }
                }
            }
        }
    }

    private static func style(_ kind: String) -> (String, Color)? {
        switch kind {
        case "pressure": ("triangle.fill", .orange)
        case "thermal": ("diamond.fill", .purple)
        default: nil
        }
    }
}
