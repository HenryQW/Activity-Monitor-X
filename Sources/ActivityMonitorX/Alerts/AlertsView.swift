import AMXCore
import SwiftUI

/// Alert rows newest first under Today, Yesterday and Earlier; dismissed rows are hidden unless shown, then dimmed: rows that were unread when someone could last start to see
/// the screen stay bold while it is shown. The sidebar search filters by app or message. Double-click or Show in
/// Apps opens Apps at the alert.
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
        let rows = alerts.listed(search: search)
        Group {
            if !rows.isEmpty {
                list(rows)
            } else if !search.isEmpty && !alerts.alerts.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if let error = alerts.error {
                ContentUnavailableView("Cannot Load Alerts", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView("No Alerts", systemImage: "checkmark.circle",
                                       description: Text("Rules run all the time, also while the app is closed."))
            }
        }
        // A new row, a dismissed row and a restored row fade in or out; a search filters the rows with no fade.
        .animation(Motion.fade(), value: alerts.alerts.map(\.id))
        .animation(Motion.fade(), value: alerts.dismissed)
        .screenTitle("Alerts", icon: .symbol("exclamationmark.triangle"))
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

    private func list(_ rows: [EventMark]) -> some View {
        let unread = _unreadAtShow.wrappedValue
        let calendar = AppTime.calendar
        let days = Dictionary(grouping: rows) { event -> Day in
            let date = Date(timeIntervalSince1970: event.ts)
            return calendar.isDateInToday(date) ? .today : calendar.isDateInYesterday(date) ? .yesterday : .earlier
        }
        return List(selection: _selected.projectedValue) {
            ForEach(Day.allCases, id: \.self) { day in
                if let events = days[day] {
                    Section(day.rawValue) {
                        ForEach(events) { event in
                            row(event, day: day, bold: unread.contains(event.id))
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            Group {
                if ids.count == 1 { Button("Show App at Alert Time", systemImage: "app.badge") { reveal(ids) } }
                if !ids.isEmpty {
                    if ids.allSatisfy(alerts.dismissed.contains) {
                        Button("Restore ^[\(ids.count) Alert](inflect: true)", systemImage: "arrow.uturn.backward") { alerts.restore(ids) }
                    } else {
                        Button("Dismiss ^[\(ids.count) Alert](inflect: true)", systemImage: "xmark.circle") { alerts.dismiss(ids) }
                    }
                }
            }
                .labelStyle(.titleAndIcon)
        } primaryAction: { reveal($0) }
    }

    private func row(_ event: EventMark, day: Day, bold: Bool) -> some View {
        let dismissed = alerts.dismissed.contains(event.id)
        return HStack {
            SeverityIcon(severity: event.severity).frame(width: 40)
            // The section names the day, so Today and Yesterday rows show the time only.
            Text(Date(timeIntervalSince1970: event.ts).formatted(date: day == .earlier ? .abbreviated : .omitted, time: .shortened))
                .monospacedDigit().frame(width: 140, alignment: .leading)
            Text(event.subject).frame(width: 160, alignment: .leading)
            Text(event.message).help(event.message).frame(maxWidth: .infinity, alignment: .leading)
        }
        .bold(bold)
        .opacity(dismissed ? 0.5 : 1)
        .swipeActions(edge: .trailing) {
            if dismissed {
                Button("Restore Alert", systemImage: "arrow.uturn.backward") { alerts.restore([event.id]) }
            } else {
                Button("Dismiss Alert", systemImage: "xmark.circle") { alerts.dismiss([event.id]) }.tint(.gray)
            }
        }
    }

    private enum Day: String, CaseIterable { case today = "Today", yesterday = "Yesterday", earlier = "Earlier" }

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
