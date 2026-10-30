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
        let pressure = isLive ? nil : points.map(\.pressureLevel).filter({ $0 > 0 }).max()
        // The worst state shown, so the closed card still warns.
        let worst = max(pressure.map(SystemState.pressureSeverity) ?? 0, SystemState.thermalSeverity(thermal))
        CardSection("System Health", summary: Text(worst == 2 ? "Critical" : worst == 1 ? "Warning" : "Normal")) {
            if let pressure {
                row("Memory pressure", SystemState.pressure(pressure), severity: SystemState.pressureSeverity(pressure))
                    .help("The highest memory pressure in the range")
                LabeledContent("Swap used", value: Metric.memory.format(points.map(\.swapUsed).max() ?? 0))
                    .monospacedDigit()
                    .help("The most swap used in the range")
            }
            row("Thermal state", SystemState.thermal(thermal), severity: SystemState.thermalSeverity(thermal))
                .help("The thermal state now")
            LabeledContent("Uptime", value: Units.uptime(info.systemUptime))
                .help("The time since this Mac started")
        }
    }

    /// A state in words, with the warning or critical icon from severity 1.
    private func row(_ title: String, _ value: String, severity: Int) -> some View {
        LabeledContent(title) {
            HStack(spacing: Layout.gap) {
                if severity > 0 { SeverityIcon(severity: severity) }
                Text(value.capitalized)
            }
        }
    }
}
