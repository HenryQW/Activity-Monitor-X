import AMXCore
import SwiftUI

/// Alerts newest first in a table, as Apps and Volumes: severity, time, the subject (the app's icon or the system part's
/// symbol, then its name) and the message. Dismissed rows are hidden unless shown, then dimmed; rows that were unread when
/// someone could last start to see the screen stay bold while it is shown. The search filters by app or message.
/// Double-click or Show in Apps opens Apps at the alert.
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
        .screenFooter(rows.isEmpty ? nil : AlertsFacts(rows: rows))
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
        return Table(rows, selection: _selected.projectedValue) {
            TableColumn("Severity") { event in cell(event, unread) { SeverityIcon(severity: event.severity) } }
                .width(min: 56, ideal: 56, max: 64)
            TableColumn("Time") { event in cell(event, unread) { Text(Self.time(event.ts)).monospacedDigit() } }
                .width(min: 110, ideal: 150, max: 180)
            TableColumn("Subject") { event in
                cell(event, unread) {
                    Label {
                        Text(event.subject)
                    } icon: {
                        if let app = event.app, event.rule.map({ !RuleName.system.contains($0) }) ?? true {
                            Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: RuleName.symbol(event.rule)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 120, ideal: 170, max: 240)
            TableColumn("Message") { event in cell(event, unread) { Text(event.message).help(event.message) } }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            Group {
                if ids.count == 1 { Button("Show App at Alert Time", systemImage: "app.badge") { reveal(ids) } }
                if !ids.isEmpty {
                    Button("Copy ^[\(ids.count) Message](inflect: true)", systemImage: "doc.on.doc") {
                        DiskItemMenu.copy(rows.filter { ids.contains($0.id) }.map(\.message).joined(separator: "\n"))
                    }
                    .help("Copy the alert messages")
                }
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

    /// A cell's content, bold while unread when shown and dimmed when dismissed.
    private func cell(_ event: EventMark, _ unread: Set<Int64>, @ViewBuilder _ content: () -> some View) -> some View {
        content().bold(unread.contains(event.id)).opacity(alerts.dismissed.contains(event.id) ? 0.5 : 1)
    }

    /// "Today, 15:42", "Yesterday, 22:31" or "21 Oct 2026, 09:12", in the app's time zone; the menu bar menu uses it too.
    static func time(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts), calendar = AppTime.calendar
        let time = date.formatted(Date.FormatStyle(time: .shortened, timeZone: AppTime.zone))
        let day = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(Date.FormatStyle(date: .abbreviated, timeZone: AppTime.zone))
        return "\(day), \(time)"
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

/// The listed alerts at a glance in the screen's footer (FT2): the last 7 days as bars by severity, then today's count,
/// the 7 days' critical and warning counts and the subject that alerted most.
private struct AlertsFacts: View {
    let rows: [EventMark]

    var body: some View {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        let week = rows.filter { Date(timeIntervalSince1970: $0.ts) >= days[0] }
        let critical = week.count { $0.severity >= 2 }
        let frequent = Dictionary(grouping: week, by: \.subject).max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }
        ScreenFooter(figures: [
            FooterFigure(label: "Today", value: rows.count { Date(timeIntervalSince1970: $0.ts) >= today }.formatted(), help: "The alerts listed today"),
            FooterFigure(label: "Critical, 7 days", value: critical.formatted(), help: "The critical alerts listed in the last 7 days",
                         severity: critical > 0 ? 2 : 0),
            FooterFigure(label: "Warnings, 7 days", value: (week.count - critical).formatted(), help: "The warnings listed in the last 7 days",
                         severity: week.count > critical ? 1 : 0),
            FooterFigure(label: frequent.map { "Most frequent, \($0.value.count)" } ?? "Most frequent", value: frequent?.key ?? "None",
                         help: "The subject with the most alerts in the last 7 days"),
        ]) {
            AlertDays(counts: days.map { day in
                let end = calendar.date(byAdding: .day, value: 1, to: day)!
                let on = week.filter { (day..<end).contains(Date(timeIntervalSince1970: $0.ts)) }
                return (on.count { $0.severity < 2 }, on.count { $0.severity >= 2 })
            })
        }
        .accessibilityLabel("Alerts summary")
    }
}

/// One bar per day, oldest first: warnings in yellow under criticals in red, on one scale.
private struct AlertDays: View {
    let counts: [(warning: Int, critical: Int)]

    var body: some View {
        let top = Double(max(counts.map { $0.warning + $0.critical }.max() ?? 0, 1))
        Canvas { context, size in
            let slot = size.width / Double(counts.count), width = slot * 0.6
            for (i, day) in counts.enumerated() {
                let x = Double(i) * slot + (slot - width) / 2
                let warning = size.height * Double(day.warning) / top, critical = size.height * Double(day.critical) / top
                context.fill(Path(CGRect(x: x, y: size.height - warning, width: width, height: warning)), with: .color(.yellow))
                context.fill(Path(CGRect(x: x, y: size.height - warning - critical, width: width, height: critical)), with: .color(.red))
            }
            context.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(Color(nsColor: .separatorColor)))
        }
        .frame(width: 112)
        .accessibilityHidden(true)
    }
}
