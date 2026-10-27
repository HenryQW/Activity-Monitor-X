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
    /// The width the Month cells take: the tiles take the same.
    private let _gridWidth = State(initialValue: 0.0)
    /// Read here, not per call, so the transition follows a change of the setting at once.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A zoom in grows the new period from the clicked cell (scale 0.86 to 1) as the old one grows away (to 1.12); a zoom out is
    /// the reverse. With Reduce Motion, or with no zoom (stepping, a new metric), it is a fade.
    private var zoomTransition: AnyTransition {
        guard !reduceMotion, let zoom = model.zoom else { return .opacity }
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
                VStack(spacing: 8) {
                    if page.period == .month {
                        CalendarTiles(page: page).frame(width: _gridWidth.wrappedValue > 0 ? _gridWidth.wrappedValue : nil).padding(.horizontal)
                    }
                    CalendarGrid(page: page, footer: footer) { if abs($0 - _gridWidth.wrappedValue) >= 1 { _gridWidth.wrappedValue = $0 } }
                }
                .coordinateSpace(.named(Self.contentSpace))
                .onGeometryChange(for: CGSize.self, of: \.size) { _size.wrappedValue = CGSize(width: max(1, $0.width), height: max(1, $0.height)) }
                .transition(zoomTransition)
            }
        }
    }
}

/// The month at a glance as cells of one height, each with the thing it is about, as Hardware's cells: the metric's
/// symbol and its mean, a clock and the busiest hour, the top app's icon and its share, the alert symbols and their counts.
/// Four in a row, two rows of two where the column is narrow.
private struct CalendarTiles: View {
    let page: CalendarPage

    var body: some View {
        let cells = page.cells
        let values = cells.flatMap(\.lines).compactMap { $0 }
        let peak = cells.compactMap { cell in cell.peak.map { (cell.lineStart($0), cell.lines[$0]!) } }.max { $0.1 < $1.1 }
        let leader = CalendarPeriod.leader(of: cells)
        let critical = page.alerts.count { $0.severity >= 2 }, warning = page.alerts.count - critical
        let label = page.metric.label
        let tiles = [
            tile(Image(systemName: page.metric.symbol).font(.title3).foregroundStyle(.secondary),
                 values.isEmpty ? "No data" : "\(page.metric.format(values.reduce(0, +) / Double(values.count))) average", label),
            tile(Image(systemName: "clock").font(.title3).foregroundStyle(.secondary),
                 peak.map { "\(page.metric.format($0.1)) at \(Date(timeIntervalSince1970: $0.0).formatted(.dateTime.hour()))" } ?? "No data",
                 peak.map { "Busiest: \(Date(timeIntervalSince1970: $0.0).formatted(.dateTime.weekday(.abbreviated).day()))" } ?? "Busiest hour"),
            tile(leader.map { Image(nsImage: AppIcon.image(for: $0.app)).resizable().frame(width: 22, height: 22) },
                 leader?.app.name ?? "No data",
                 leader.map { "\($0.share.formatted(.percent.precision(.fractionLength(0)))) of all \(label)" } ?? "Top app"),
            tile(HStack(spacing: 1) {
                    if critical > 0 { SeverityIcon(severity: 2) }
                    if warning > 0 { SeverityIcon(severity: 1) }
                    if page.alerts.isEmpty { Image(systemName: "bell").font(.title3).foregroundStyle(.secondary) }
                 },
                 page.alerts.isEmpty ? "None" : [critical > 0 ? "\(critical) critical" : nil, warning > 0 ? "\(warning) warning\(warning == 1 ? "" : "s")" : nil]
                    .compactMap { $0 }.joined(separator: ", "),
                 "Alerts"),
        ]
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Layout.inset) { ForEach(tiles.indices, id: \.self) { tiles[$0].frame(minWidth: 150) } }
            Grid(horizontalSpacing: Layout.inset, verticalSpacing: Layout.inset) {
                GridRow { tiles[0]; tiles[1] }
                GridRow { tiles[2]; tiles[3] }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ icon: (some View)?, _ value: String, _ note: String) -> AnyView {
        AnyView(HStack(spacing: 8) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).fontWeight(.semibold).monospacedDigit()
                Text(note).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .partCell(padding: Layout.inset)
        .accessibilityElement(children: .combine))
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
