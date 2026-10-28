import AMXCore
import AppKit
import Observation
import SwiftUI

/// The menu bar readout, read in the app every 5 s (M4-D10): no XPC, so `amxd` keeps its 5 s tick.
@Observable @MainActor
final class MenuBarReadout {
    struct Percents: Equatable {
        let cpu: Int
        let pressure: Int
        let level: Int

        /// The kernel level: 1 normal, 2 warning, 4 critical.
        var levelWord: String { level == 1 ? "Normal" : level == 2 ? "Warning" : "Critical" }
    }

    /// Nil until the second sample: CPU needs two.
    private(set) var percents: Percents?

    func run() async {
        let sampler = SystemSampler()
        _ = sampler.readout(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let r = sampler.readout(now: ProcessInfo.processInfo.systemUptime)
            let next = Percents(cpu: Int(r.cpu.rounded()), pressure: Int(r.pressurePct.rounded()), level: r.pressureLevel)
            if next != percents { percents = next }
        }
    }
}

/// CPU and memory pressure in the menu bar; "…" until the first real reading, never 0 %. A warning glyph shows only
/// while an unread alert exists; it is part of the template image, so it has no colour (D25). It draws over the status
/// button, which it sizes and names.
struct MenuBarLabel: View {
    let menu: StatusMenu
    @Environment(MenuBarReadout.self) private var readout
    @Environment(AlertsModel.self) private var alerts
    @Environment(Selection.self) private var selection
    @Environment(Preferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let p = readout.percents
        let cpu = p.map { "\($0.cpu)%" } ?? "…", pressure = p.map { "\($0.pressure)%" } ?? "…"
        let unread = alerts.unread > 0
        let spoken = (p.map { "CPU \($0.cpu) percent, memory pressure \($0.pressure) percent" + ($0.level > 1 ? ", \($0.levelWord)" : "") }
            ?? "Activity Monitor X")
            + (unread ? ", unread alert" : "")
        content(cpu: cpu, pressure: pressure, unread: unread)
            .fixedSize()
            .padding(.horizontal, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { menu.item.length = $0 }
            .accessibilityHidden(true)
            .onChange(of: spoken, initial: true) { menu.item.button?.setAccessibilityLabel(spoken) }
            // The label lives for the app's whole life, so the menu bar and notifications can reopen a closed window.
            .onAppear {
                selection.openMain = { [openWindow] in openWindow(id: "main"); NSApp.activate() }
                menu.openSettings = openSettings
            }
    }

    /// CPU over memory pressure in small type (MB2, D81): a dot for an unread alert keeps its own slot, and each number
    /// keeps the width of "100%", so nothing in the menu bar moves as the values change. The numbers keep the menu bar's
    /// own colour; a bar before a number marks a warning (yellow) or critical (red) level (the system CPU rule, the memory
    /// pressure level), as coloured text on a light menu bar is too faint to read (WL3). In greyscale the bar and the dot
    /// have the menu bar's colour.
    private func content(cpu: String, pressure: String, unread: Bool) -> some View {
        let p = readout.percents, rule = alerts.rules.systemCPU
        let cpuLevel = p.map { rule.level(Double($0.cpu)) } ?? 0
        let memoryLevel = p.map { SystemState.pressureSeverity($0.level) } ?? 0
        let row = { (label: String, value: String, level: Int) in
            GridRow {
                Text(label).font(.system(size: 8, weight: .semibold))
                HStack(spacing: 2) {
                    Capsule().fill(color(level)).frame(width: 4, height: 9).opacity(level > 0 ? 1 : 0)
                    ZStack(alignment: .trailing) { Text("100%").hidden(); Text(value) }
                }
            }
        }
        return HStack(spacing: 4) {
            Circle().fill(color(alerts.hasUnreadCritical ? 2 : 1)).frame(width: 5, height: 5).opacity(unread ? 1 : 0)
            Grid(alignment: .trailing, horizontalSpacing: 3, verticalSpacing: -2) {
                row("CPU", cpu, cpuLevel)
                row("MEM", pressure, memoryLevel)
            }
            .font(.system(size: 9.5, weight: .medium))
        }
        .monospacedDigit()
    }

    private func color(_ level: Int) -> Color {
        guard preferences.menuBarColor, level > 0 else { return .primary }
        return level >= 2 ? .red : .yellow
    }
}
