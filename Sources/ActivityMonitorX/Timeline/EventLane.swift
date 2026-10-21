import AMXCore
import Charts
import SwiftUI

/// Pressure ▲ and thermal ◆ markers on the chart's x scale, in the headroom strip at the top of the plot. Shape is the
/// kind, colour the severity: yellow warns, red is critical; the app palette uses neither.
struct EventLane: View {
    let events: [EventMark]
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geo in
            if let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                ForEach(events.indices, id: \.self) { i in
                    let event = events[i]
                    if case let (symbol, color)? = Self.style(event),
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

    private static func style(_ event: EventMark) -> (String, Color)? {
        let symbol: String, warning: Int, critical: Int
        switch event.kind {
        case "pressure": (symbol, warning, critical) = ("triangle.fill", 1, 2)
        // Thermal "fair" (1) is not yet a warning.
        case "thermal": (symbol, warning, critical) = ("diamond.fill", 2, 3)
        default: return nil
        }
        return (symbol, event.severity >= critical ? .red : event.severity >= warning ? .yellow : .secondary)
    }
}
