import AMXCore
import SwiftUI

/// The Calendar screen: the metric summed over all apps (or the apps the search matches, or one group) as one line per hour
/// in a cell for a day (Month), six hours (Week) or an hour (Day), and one line per minute for an hour. A click selects
/// a cell for the inspector, a drag a span, a double-click opens the finer period. Range does not apply here.
struct CalendarView: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @Environment(GroupsModel.self) private var groups
    @Environment(Preferences.self) private var preferences
    @Environment(AlertsModel.self) private var alerts

    /// What a load reads; a new value starts the screen's task again. Each period has its own intervals.
    private struct Load: Equatable {
        let interval: DateInterval
        let metric: Metric
        let filter: CalendarFilter
        /// The chosen zone (with the count of system zone changes) and weekday as the preferences hold them, so a change draws this view again; 0 follows the system.
        let zone: String
        let weekday: Int
        /// The levels the cells colour by.
        let cpuRule: AlertRules.SystemCPU
    }

    /// The shown group, if the stored one still exists.
    private var group: ProcessGroup? {
        if case .group(let id) = model.show { groups.groups.first { $0.id == id } } else { nil }
    }

    private var filter: CalendarFilter { CalendarFilter(query: selection.search, group: group) }

    static func showName(_ show: CalendarShow, groups: [ProcessGroup]) -> String {
        switch show {
        case .busiest: "Busiest App"
        case .all: "All Apps"
        case .group(let id): groups.first { $0.id == id }?.name ?? "Busiest App"
        }
    }

    private var footer: CalendarFooter {
        switch model.show {
        case .busiest: group == nil ? .busiest : .none
        case .all: .none
        case .group: group.map(CalendarFooter.group) ?? .busiest
        }
    }

    var body: some View {
        let load = Load(interval: model.interval, metric: history.metric, filter: filter, zone: preferences.zoneKey,
                        weekday: preferences.firstWeekday ?? 0, cpuRule: alerts.rules.systemCPU)
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaBar(edge: .top, spacing: 0) {
                CalendarHeader(title: title(model.period, model.interval), shortTitle: shortTitle(model.period, model.interval)).padding(Layout.inset)
            }
        .screenTitle("Calendar", subtitle: Text(subtitle), icon: .symbol("calendar"))
        .task(id: load) {
            await model.run(metric: load.metric, filter: load.filter, rules: alerts.rules)
        }
        .onChange(of: selection.refreshes) { Task { await model.load(metric: history.metric, filter: filter, rules: alerts.rules) } }
        .onChange(of: model.interval) { model.selected = nil }
        .focusable()
        .focusEffectDisabled()
        .onExitCommand { model.zoomOut() }
        // Day and Hour: the arrow keys move the selected bar, with Shift they stretch the span.
        .onMoveCommand { direction in
            let extend = NSEvent.modifierFlags.contains(.shift)
            switch direction {
            case .left: model.moveBar(-1, extend: extend)
            case .right: model.moveBar(1, extend: extend)
            default: break
            }
        }
        .onAppear { _monitor.wrappedValue = backMonitor() }
        .onDisappear { _monitor.wrappedValue.map(NSEvent.removeMonitor); _monitor.wrappedValue = nil }
    }

    private let _monitor = State<Any?>(initialValue: nil)

    /// The mouse back button and a swipe to the right in the main window zoom out, as Back does.
    private func backMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [model] event in
            let back = event.type == .swipe ? event.deltaX < 0 : event.buttonNumber == 3
            guard back, event.window === MainWindowRef.window else { return event }
            MainActor.assumeIsolated { model.zoomOut() }
            return nil
        }
    }

    /// What the cells name, and the zone when it is not system time or has extra labels.
    private var subtitle: String {
        var parts = [Self.showName(model.show, groups: groups.groups)]
        let zone = AppTime.zone, at = Date()
        if preferences.timeZoneID != nil {
            parts.append("\(ZoneLabel.abbreviation(zone, at: at)) (forced)")
        } else if model.period != .month, !preferences.extraZoneIDs.isEmpty {
            let extras = preferences.extraZoneIDs.compactMap(TimeZone.init(identifier:)).map { ZoneLabel.abbreviation($0, at: at) }
            parts.append(([ZoneLabel.abbreviation(zone, at: at)] + extras).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed:
            HelperUnavailable()
        case .empty where !selection.search.isEmpty:
            ContentUnavailableView.search(text: selection.search)
        case .empty:
            ContentUnavailableView("No Data", systemImage: "calendar",
                                   description: Text("No history was recorded in this \(model.period.rawValue)."))
        case .ready:
            if let page = model.page {
                VStack(spacing: 8) {
                    if page.period == .month { CalendarTiles(page: page).padding(.horizontal) }
                    CalendarGrid(page: page, footer: footer)
                }
            }
        }
    }

    /// The title for a narrow bar: "Oct 2026", "20 to 26 Oct", "Thu 22 Oct", "22 Oct, 9 AM".
    private func shortTitle(_ period: CalendarPeriod, _ interval: DateInterval) -> String {
        switch period {
        case .hour: return interval.start.formatted(.dateTime.day().month(.abbreviated).hour())
        case .day: return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day())) to \(last.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: return interval.start.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    private func title(_ period: CalendarPeriod, _ interval: DateInterval) -> String {
        switch period {
        case .hour: return interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour())
        case .day: return interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) to \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month: return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }
}

/// The month at a glance: its mean, its busiest hour, its busiest app and its alerts.
private struct CalendarTiles: View {
    @Environment(HistoryModel.self) private var history
    let page: CalendarPage

    var body: some View {
        let cells = page.cells
        let values = cells.flatMap(\.lines).compactMap { $0 }
        let peak = cells.compactMap { cell in cell.peak.map { (cell.lineStart($0), cell.lines[$0]!) } }.max { $0.1 < $1.1 }
        let leader = CalendarPeriod.leader(of: cells)
        let critical = page.alerts.count { $0.severity >= 2 }
        HStack(alignment: .top, spacing: 12) {
            tile("Average \(page.metric.label)", values.isEmpty ? "No data" : page.metric.format(values.reduce(0, +) / Double(values.count)),
                 "this month")
            tile("Busiest hour", peak.map { Date(timeIntervalSince1970: $0.0).formatted(.dateTime.weekday(.abbreviated).day().hour()) } ?? "No data",
                 peak.map { page.metric.format($0.1) } ?? "")
            tile("Top app", leader?.app.name ?? "No data", leader.map { "\(($0.share).formatted(.percent.precision(.fractionLength(0)))) of all \(page.metric.label)" } ?? "")
            tile("Alerts", page.alerts.count.formatted(), critical > 0 ? "\(critical.formatted()) critical" : "none critical")
        }
    }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.7)
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
