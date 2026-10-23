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
            // The newest unread alert, one line; a click reads it, as opening Alerts does.
            if let event = alerts.latestUnread {
                Button {
                    alerts.markAllRead()
                    reveal(event)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SeverityIcon(severity: event.severity)
                        Text(event.message).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(Date(timeIntervalSince1970: event.ts).formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .help("\(event.message). Show this alert in Apps.")
                Divider()
            }
            HStack(alignment: .top) {
                ReadoutGauge(title: "CPU", percent: readout.percents?.cpu) {
                    SparklineShape(values: readout.cpuHistory).stroke(.tint, lineWidth: 1).frame(width: 120, height: 24)
                }
                ReadoutGauge(title: "Memory Pressure", percent: readout.percents?.pressure) {
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
            .help("Open the Activity Monitor X settings")
            Button("Quit Activity Monitor X", systemImage: "power") { NSApp.terminate(nil) }
                .help("Quit Activity Monitor X. The helper continues to record history.")
        }
        .buttonStyle(.borderless)
        .labelStyle(IconColumnLabelStyle())
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

    /// The top line already shows the newest unread alert.
    @ViewBuilder private var recentAlerts: some View {
        let unreadID = alerts.latestUnread?.id
        let rows = Array(alerts.alerts.filter { $0.id != unreadID }.prefix(3))
        if rows.isEmpty {
            Text(alerts.alerts.isEmpty ? "No alerts" : "No other alerts").foregroundStyle(.secondary)
        } else {
            ForEach(rows, id: \.id) { event in
                Button {
                    reveal(event)
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

    private func reveal(_ event: EventMark) {
        open()
        selection.reveal(event, history: history, rules: alerts.rules)
    }
}

/// A capacity ring with its percent inside, under its title. CPU is already a share of all cores, so 0 to 100 fits
/// both. "…" until the first reading.
private struct ReadoutGauge<Detail: View>: View {
    let title: String
    let percent: Int?
    @ViewBuilder let detail: Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline).accessibilityHidden(true)
            Gauge(value: Double(percent ?? 0), in: 0...100) {
                Text(title)
            } currentValueLabel: {
                Text(percent.map { "\($0)%" } ?? "…")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent ?? 0)))
                    .animation(reduceMotion ? nil : .default, value: percent)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityValue(percent.map { "\($0) percent" } ?? "No reading yet")
            detail
        }
        .frame(maxWidth: .infinity)
    }
}

/// Symbols differ in width; a fixed icon column lines up the action titles, as in a menu.
private struct IconColumnLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.frame(width: 18)
            configuration.title
        }
    }
}
