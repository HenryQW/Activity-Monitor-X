import AMXCore
import SwiftUI

/// The worst memory pressure and the most swap in the range (or span), from the system samples, and the thermal state
/// and uptime now. Live loads no system samples, so it shows the last two only.
struct SystemHealthCard: View {
    @Environment(HistoryModel.self) private var history
    let isLive: Bool

    var body: some View {
        let span = history.span
        let points = history.system.filter { point in span.map { $0.contains(point.bucket) } ?? true }
        let info = ProcessInfo.processInfo
        let thermal = info.thermalState.rawValue
        Section("System Health") {
            if !isLive, let pressure = points.map(\.pressureLevel).filter({ $0 > 0 }).max() {
                row("Memory Pressure", SystemState.pressure(pressure), severity: pressure >= 4 ? 2 : pressure >= 2 ? 1 : 0)
                    .help("The highest memory pressure in the range")
                LabeledContent("Swap Used", value: Metric.memory.format(points.map(\.swapUsed).max() ?? 0))
                    .monospacedDigit()
                    .help("The most swap used in the range")
            }
            row("Thermal State", SystemState.thermal(thermal), severity: thermal >= 3 ? 2 : thermal >= 2 ? 1 : 0)
                .help("The thermal state now")
            LabeledContent("Uptime", value: Duration.seconds(info.systemUptime)
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
                .help("The time since this Mac started")
        }
    }

    /// A state in words, with the warning or critical icon from severity 1.
    private func row(_ title: String, _ value: String, severity: Int) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                if severity > 0 { SeverityIcon(severity: severity) }
                Text(value.capitalized)
            }
        }
    }
}
