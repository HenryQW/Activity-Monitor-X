import AMXCore
import AppKit
import SwiftUI

/// The menu bar popover: the readout, top apps and recent alerts. It asks `amxd` for live data only while open (Review
/// Focus 6): the poll runs only while the panel is active, so it stops on close even if SwiftUI keeps the view, and
/// `amxd` drops to its 5 s tick 3 s after the last request.
struct MenuBarContent: View {
    let client: DaemonClient
    @Environment(MenuBarReadout.self) private var readout
    @Environment(AlertsModel.self) private var alerts
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.appearsActive) private var appearsActive
    private let _top = State<[LiveTop.Row]?>(initialValue: nil)
    private let _unreachable = State(initialValue: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("CPU").font(.headline)
                    Text(readout.percents.map { "\($0.cpu)%" } ?? "…").font(.title2)
                    SparklineShape(values: readout.cpuHistory).stroke(.tint, lineWidth: 1).frame(width: 120, height: 24)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Memory Pressure").font(.headline)
                    Text(readout.percents.map { "\($0.pressure)%" } ?? "…").font(.title2)
                    Text(readout.percents?.levelWord ?? "").foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            Divider()
            Text("Top Apps").font(.headline)
            topApps
            Divider()
            Text("Recent Alerts").font(.headline)
            recentAlerts
            Divider()
            Button("Open Activity Monitor X", systemImage: "macwindow") { open() }
                .help("Open the main window")
            // `SettingsLink` does not activate the app, so the window would open behind the frontmost app (Task 0).
            Button("Settings…", systemImage: "gearshape") {
                NSApp.activate()
                openSettings()
            }
            .help("Open the settings")
            Button("Quit Activity Monitor X", systemImage: "power") { NSApp.terminate(nil) }
                .help("Quit Activity Monitor X. The helper continues to record history.")
        }
        .buttonStyle(.borderless)
        .padding(12)
        .frame(width: 320)
        .task(id: appearsActive) {
            guard appearsActive else { return }
            while !Task.isCancelled {
                do {
                    if let snapshot = try await client.live() { _top.wrappedValue = LiveTop.apps(snapshot, limit: 5) }
                    _unreachable.wrappedValue = false
                } catch {
                    _unreachable.wrappedValue = true
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder private var topApps: some View {
        if _unreachable.wrappedValue {
            Text("Helper not reachable").foregroundStyle(.secondary)
        } else if let rows = _top.wrappedValue {
            ForEach(rows, id: \.app.key) { row in
                HStack(spacing: 6) {
                    Image(nsImage: AppIcon.image(for: row.app)).resizable().frame(width: 16, height: 16)
                    Text(row.app.name).lineLimit(1)
                    Spacer()
                    Text(Metric.cpu.format(row.cpu)).frame(width: 56, alignment: .trailing)
                    Text(Metric.memory.format(Double(row.mem))).frame(width: 72, alignment: .trailing)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var recentAlerts: some View {
        if alerts.alerts.isEmpty {
            Text("No alerts").foregroundStyle(.secondary)
        } else {
            ForEach(alerts.alerts.prefix(3), id: \.id) { event in
                Button {
                    open()
                    selection.reveal(event, history: history, rules: alerts.rules)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SeverityIcon(severity: event.severity)
                        VStack(alignment: .leading) {
                            Text(event.subject).lineLimit(1)
                            Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(Date(timeIntervalSince1970: event.ts).formatted(date: .omitted, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .help("Show this alert in Apps")
            }
        }
    }

    private func open() {
        selection.openMain?()
        dismiss()
    }
}
