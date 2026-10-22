import AMXCore
import SwiftUI

/// Alert rows newest first, listed as a message list: rows that were unread when someone could last start to see
/// the screen stay bold while it is shown. The sidebar search filters by app or message. Double-click or Show in
/// Timeline opens the Timeline at the alert.
struct AlertsView: View {
    @Environment(AlertsModel.self) private var alerts
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    /// False while another app is active or the screen is locked: nobody reads the rows then.
    @Environment(\.appearsActive) private var appearsActive
    private let _selected = State<Set<Int64>>(initialValue: [])
    private let _unreadAtShow = State<Set<Int64>>(initialValue: [])

    var body: some View {
        let search = selection.search
        let rows = search.isEmpty ? alerts.alerts : alerts.alerts.filter {
            $0.subject.localizedStandardContains(search) || $0.message.localizedStandardContains(search)
                || $0.app.map { AppSearch.matches($0, search) } == true
        }
        Group {
            if !rows.isEmpty {
                table(rows)
            } else if !alerts.alerts.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if let error = alerts.error {
                ContentUnavailableView("Cannot Load Alerts", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView("No Alerts", systemImage: "checkmark.circle",
                                       description: Text("Rules run all the time, also while the app is closed."))
            }
        }
        .navigationTitle("Alerts")
        .onAppear { show(appearsActive) }
        .onChange(of: appearsActive) { _, active in show(active) }
        .onDisappear { alerts.shown = false }
    }

    /// Someone can see the rows: the unread ones turn bold and are read.
    private func show(_ visible: Bool) {
        alerts.shown = visible
        guard visible else { return }
        _unreadAtShow.wrappedValue = alerts.unreadIDs
        alerts.markAllRead()
    }

    private func table(_ rows: [EventMark]) -> some View {
        let unread = _unreadAtShow.wrappedValue
        return Table(rows, selection: _selected.projectedValue) {
            TableColumn("Severity") { event in
                SeverityIcon(severity: event.severity)
            }
            .width(min: 64, ideal: 64, max: 72)
            .alignment(.center)
            TableColumn("Time") { event in
                Text(Date(timeIntervalSince1970: event.ts).formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
                    .bold(unread.contains(event.id))
            }
            .width(min: 120, ideal: 150, max: 180)
            TableColumn("App") { event in
                Text(event.subject).bold(unread.contains(event.id))
            }
            .width(min: 100, ideal: 160, max: 260)
            TableColumn("Message") { event in
                Text(event.message).bold(unread.contains(event.id))
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if ids.count == 1 { Button("Show in Timeline") { reveal(ids) } }
        } primaryAction: { reveal($0) }
    }

    private func reveal(_ ids: Set<Int64>) {
        guard ids.count == 1, let event = alerts.alerts.first(where: { ids.contains($0.id) }) else { return }
        selection.reveal(event, history: history, rules: alerts.rules)
    }
}

/// An alert's severity as shape and colour, with a spoken label: warning (1) or critical (2).
struct SeverityIcon: View {
    let severity: Int

    var body: some View {
        let label = severity >= 2 ? "Critical" : "Warning"
        Image(systemName: severity >= 2 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(severity >= 2 ? Color.red : .yellow)
            .accessibilityLabel(label)
            .help(label)
    }
}
