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

    nonisolated static let historyLength = 60

    /// Nil until the second sample: CPU needs two.
    private(set) var percents: Percents?
    /// The last 60 CPU readings, oldest first: 5 min at the 5 s tick. The menu shows the same buffer.
    private(set) var cpuHistory: [Double] = []

    func run() async {
        let sampler = SystemSampler()
        _ = sampler.readout(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let r = sampler.readout(now: ProcessInfo.processInfo.systemUptime)
            let new = Percents(cpu: Int(r.cpu.rounded()), pressure: Int(r.pressurePct.rounded()), level: r.pressureLevel)
            cpuHistory.append(r.cpu, keepingLast: Self.historyLength)
            percents = new
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
        let spoken = (p.map { "CPU \($0.cpu) percent, memory pressure \($0.pressure) percent" } ?? "Activity Monitor X")
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

    @ViewBuilder private func content(cpu: String, pressure: String, unread: Bool) -> some View {
        if preferences.menuBarStyle == .chart {
            Image(nsImage: image(cpu: cpu, pressure: pressure, unread: unread))
        } else {
            let glyph = unread ? Text("\(Image(systemName: "exclamationmark.triangle")) ") : Text("")
            Text("\(Image(systemName: "cpu")) \(cpu) \(glyph)\(Image(systemName: "memorychip")) \(pressure)").monospacedDigit()
        }
    }

    /// A template image: the menu bar sets the colour from its alpha, so light, dark and tint stay right.
    private func image(cpu: String, pressure: String, unread: Bool) -> NSImage {
        let renderer = ImageRenderer(content: HStack(spacing: 3) {
            Image(systemName: "cpu")
            Text(cpu)
            if unread { Image(systemName: "exclamationmark.triangle").imageScale(.small) }
            SparklineShape(values: readout.cpuHistory).stroke(lineWidth: 1).frame(width: 24, height: 12)
            Image(systemName: "memorychip")
            Text(pressure)
        }
        .font(.system(size: 13)).monospacedDigit().foregroundStyle(.black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
