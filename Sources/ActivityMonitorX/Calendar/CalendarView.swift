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
    @Environment(ToolbarFit.self) private var fit

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
            .animation(Motion.fade(0.28), value: model.state)
            .safeAreaBar(edge: .top, spacing: 0) {
                CalendarHeader().padding(Layout.inset)
            }
            .screenFooter(model.state == .ready ? model.page.map(CalendarFacts.init) : nil)
        .screenTitle("Calendar", subtitle: Text(subtitle), icon: .symbol("calendar"))
        // Outside the title pill's toolbar, so Back sits between the Sidebar button and the pill.
        .toolbar { ToolbarItem(placement: .navigation) { CalendarBackButton().fitBack(fit) } }
        .task(id: load) {
            await model.run(metric: load.metric, filter: load.filter, rules: alerts.rules)
        }
        .onChange(of: selection.refreshes) { Task { await model.load(metric: history.metric, filter: filter, rules: alerts.rules) } }
        .onChange(of: model.interval) { model.selected = nil }
        // The new period is in (or failed): the zoom is over.
        .onChange(of: model.state) { _, state in if state != .loading { model.zoom = nil } }
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

    /// Where the screen is: "October 2026", "Week of 20 Oct", "Thu 22 Oct", "Thu 22 Oct, 3 PM".
    private var subtitle: String {
        let start = model.interval.start
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return switch model.period {
        case .month: start.formatted(.dateTime.month(.wide).year())
        case .week: "Week of " + start.formatted(.dateTime.day().month(.abbreviated))
        case .day: day
        case .hour: day + ", " + start.formatted(.dateTime.hour())
        }
    }

    /// The content's coordinate space: a zoom grows from the double-click in it.
    nonisolated static let contentSpace = "calendarContent"
    private let _size = State(initialValue: CGSize(width: 1, height: 1))
    /// Read here, not per call, so the transition follows a change of the setting at once.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A zoom in grows the new period from the clicked cell (scale 0.86 to 1) as the old one grows away (to 1.12); a zoom out is
    /// the reverse. With Reduce Motion or Low Power Mode, or with no zoom (stepping, a new metric), it is a fade.
    private var zoomTransition: AnyTransition {
        guard !reduceMotion, Motion.on, let zoom = model.zoom else { return .opacity }
        let size = _size.wrappedValue
        let anchor = UnitPoint(x: (zoom.from?.x ?? size.width / 2) / size.width, y: (zoom.from?.y ?? size.height / 2) / size.height)
        return .asymmetric(insertion: .scale(scale: zoom.into ? 0.86 : 1.12, anchor: anchor).combined(with: .opacity),
                           removal: .scale(scale: zoom.into ? 1.12 : 0.86, anchor: anchor).combined(with: .opacity))
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
                CalendarGrid(page: page, footer: footer)
                .coordinateSpace(.named(Self.contentSpace))
                .onGeometryChange(for: CGSize.self, of: \.size) { _size.wrappedValue = CGSize(width: max(1, $0.width), height: max(1, $0.height)) }
                .transition(zoomTransition)
            }
        }
    }
}

/// The page at a glance in the screen's footer (FT2): the page's cells as a heat grid, then the mean, the busiest bucket,
/// the top app with its share and the alert counts.
private struct CalendarFacts: View {
    let page: CalendarPage

    var body: some View {
        let cells = page.cells
        let values = cells.flatMap(\.lines).compactMap { $0 }
        let peak = cells.compactMap { cell in cell.peak.map { (cell.lineStart($0), cell.lines[$0]!) } }.max { $0.1 < $1.1 }
        let leader = CalendarPeriod.leader(of: cells)
        let critical = page.alerts.count { $0.severity >= 2 }, warning = page.alerts.count - critical
        let label = page.metric.label
        // The day with the hour across days, the time within one.
        let when = page.period == .month || page.period == .week
            ? Date.FormatStyle.dateTime.weekday(.abbreviated).day().hour() : Date.FormatStyle.dateTime.hour().minute()
        ScreenFooter(figures: [
            FooterFigure(label: "Average \(label)", value: values.isEmpty ? "No data" : page.metric.format(values.reduce(0, +) / Double(values.count)),
                         help: "The mean of the \(page.period.rawValue)'s buckets"),
            FooterFigure(label: peak.map { "Busiest, " + Date(timeIntervalSince1970: $0.0).formatted(when) } ?? "Busiest",
                         value: peak.map { page.metric.format($0.1) } ?? "No data", help: "The highest bucket of the \(page.period.rawValue)"),
            FooterFigure(label: leader.map { "\($0.share.formatted(.percent.precision(.fractionLength(0)))) of all \(label)" } ?? "Top app",
                         value: leader?.app.name ?? "No data", help: "The app with the largest share of the \(page.period.rawValue)"),
            FooterFigure(label: "Alerts",
                         value: page.alerts.isEmpty ? "None" : [critical > 0 ? "\(critical) critical" : nil,
                                                                warning > 0 ? "\(warning) warning\(warning == 1 ? "" : "s")" : nil]
                            .compactMap { $0 }.joined(separator: ", "),
                         help: "The alerts in the \(page.period.rawValue)", severity: critical > 0 ? 2 : warning > 0 ? 1 : 0),
        ]) {
            CalendarHeat(page: page)
        }
        .accessibilityLabel("\(page.period.rawValue.capitalized) summary")
    }
}

/// The page's cells as a heat grid in the grid's own rows and columns: each cell the accent at its mean's share of the
/// highest cell, a cell with no data the empty fill, nothing outside the month.
private struct CalendarHeat: View {
    let page: CalendarPage

    var body: some View {
        let grid = page.grid
        let top = grid.joined().compactMap { $0?.value }.max() ?? 0
        Canvas { context, size in
            let rows = grid.count, columns = grid.map(\.count).max() ?? 1
            let gap = 2.0, w = (size.width - gap * Double(columns - 1)) / Double(columns), h = (size.height - gap * Double(rows - 1)) / Double(rows)
            for (r, row) in grid.enumerated() {
                for (c, cell) in row.enumerated() {
                    guard let cell else { continue }
                    let rect = CGRect(x: Double(c) * (w + gap), y: Double(r) * (h + gap), width: w, height: h)
                    let shape = Path(roundedRect: rect, cornerRadius: 1.5)
                    context.fill(shape, with: .color(PartStyle.package))
                    if let value = cell.value, top > 0 { context.fill(shape, with: .color(.accentColor.opacity(0.2 + 0.8 * value / top))) }
                }
            }
        }
        .frame(width: Double(page.grid.map(\.count).max() ?? 1) * 12, height: 32)
        .accessibilityHidden(true)
    }
}

/// The standard toolbar Back: one level up with the parent's selection. Always there on this screen and disabled at Month,
/// so nothing appears or moves.
private struct CalendarBackButton: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let wider = model.widerName
        let hint = wider.map { "Go back to \($0)" } ?? "Month is the widest view"
        Button("Back", systemImage: "chevron.left") { model.zoomOut() }
            .labelStyle(.iconOnly)
            .disabled(wider == nil)
            .help(hint)
            .accessibilityHint(hint)
    }
}
