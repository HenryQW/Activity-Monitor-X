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
    }

    /// Nil until the second sample: CPU needs two.
    private(set) var percents: Percents?

    func run() async {
        let sampler = SystemSampler()
        _ = sampler.readout(now: Date().timeIntervalSince1970)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let r = sampler.readout(now: Date().timeIntervalSince1970)
            let new = Percents(cpu: Int(r.cpu.rounded()), pressure: Int(r.pressurePct.rounded()))
            // Observation redraws on every set, equal or not.
            if new != percents { percents = new }
        }
    }
}

/// CPU and memory pressure in the menu bar; "…" until the first real reading, never 0 %.
struct MenuBarLabel: View {
    @Environment(MenuBarReadout.self) private var readout
    @Environment(Selection.self) private var selection
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let p = readout.percents
        let cpu = p.map { "\($0.cpu)%" } ?? "…", pressure = p.map { "\($0.pressure)%" } ?? "…"
        Text("\(Image(systemName: "cpu")) \(cpu) \(Image(systemName: "memorychip")) \(pressure)")
            .monospacedDigit()
            .accessibilityLabel(p.map { "CPU \($0.cpu) percent, memory pressure \($0.pressure) percent" } ?? "Activity Monitor X")
            // Runs while the item is hidden too (Task 0 probe 3); two cheap reads every 5 s.
            .task { await readout.run() }
            // The label lives for the app's whole life, so the menu bar and notifications can reopen a closed window.
            .onAppear { selection.openMain = { [openWindow] in openWindow(id: "main"); NSApp.activate() } }
    }
}
