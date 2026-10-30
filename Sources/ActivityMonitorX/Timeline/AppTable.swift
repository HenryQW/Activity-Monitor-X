import AMXCore
import SwiftUI

/// Apps ranked for the span (or the whole range), each expandable to its processes, with the range's trend and a pin
/// button; pin or unpin from the row button or the context menu.
struct AppTable: View {
    let ranking: [AppRank]
    /// The chart's top apps; other apps get no dot.
    let colors: [AppKey: Color]
    let metric: Metric
    /// Each app's line over the whole range.
    let sparklines: [AppKey: [Double]]
    /// The group's total average; the table then shows each row's share of it.
    var shareTotal: Double? = nil
    /// Live re-ranks every 5 s: the row order then holds while the pointer is over the table (D19).
    var live = false
    /// Reports the app key of the row under the pointer (true) and leaving it (false), for the chart to highlight.
    var hover: (String, Bool) -> Void = { _, _ in }

    @Environment(Selection.self) private var selection
    @Environment(HistoryModel.self) private var history
    @Environment(AlertsModel.self) private var alerts
    private let _expanded = State<Set<Row.ID>>(initialValue: [])
    private let _sortOrder = State(initialValue: [KeyPathComparator(\Row.average, order: .reverse)])
    /// Row positions (apps and processes) while the order holds; nil while the table sorts.
    private let _held = State<[Row.ID: Int]?>(initialValue: nil)
    private let _showIdle = State(initialValue: false)
    /// Set by a quiet toggle, whose rows change when the reload ends; the next row change then animates, or none within 10 s (D67).
    private let _afterQuiet = State(initialValue: false)
    private let _quietReset = State<Task<Void, Never>?>(initialValue: nil)
    /// An app to scroll to once its row exists: a reveal can change the range first.
    private let _pendingScroll = State(initialValue: false)
    private let _scrollReset = State<Task<Void, Never>?>(initialValue: nil)
    /// The table's own click is changing the selected app: it is already in view, so no scroll.
    private let _fromTable = State(initialValue: false)
    /// The app whose Trend sparkline is under the pointer and the pointer's place in the table; the preview shows after a
    /// short delay (`_sparkShown`), as a pointer crossing the column must not flash one per row.
    private let _spark = State<(app: AppKey, point: CGPoint)?>(initialValue: nil)
    private let _sparkShown = State<String?>(initialValue: nil)
    /// Only the hidden columns are kept between tables. A kept `TableColumnCustomization` also keeps each column's width,
    /// so a new table narrower than the last (inspector shown) scrolled Peak, Trend and Pin out of view (measured).
    private let _columns = State(initialValue: AppTable.customization())
    private static let hiddenKey = "appTableHiddenColumns"
    private static let hideable = ["average", "peak", "share", "trend", "pin"]
    /// Columns hidden by default; only the ones turned on are kept.
    private static let shownKey = "appTableShownColumns"
    private static let optional = ["pid", "user"]

    private static func customization() -> TableColumnCustomization<Row> {
        var columns = TableColumnCustomization<Row>()
        for id in UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [] { columns[visibility: id] = .hidden }
        for id in UserDefaults.standard.stringArray(forKey: shownKey) ?? [] { columns[visibility: id] = .visible }
        return columns
    }

    /// User names by uid: `getpwuid` reads the directory service.
    private static var userNames: [UInt32: String] = [:]

    private static func userName(_ uid: UInt32?) -> String {
        guard let uid else { return "" }
        if let name = userNames[uid] { return name }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        userNames[uid] = name
        return name
    }

    var body: some View {
        // Once per body: each test formats three values.
        let idle = Set(ranking.filter(isIdle).map(\.app))
        let sorted = rows(sortedBy: _sortOrder.wrappedValue, idle: idle)
        let held = live ? _held.wrappedValue : nil
        let rows = held.map { Self.holding(sorted, at: $0) } ?? sorted
        let details = AppKey.details(for: ranking.map(\.app))
        // One y scale per metric: 0 to the largest value in view, so rows compare with each other.
        let top = ranking.compactMap { sparklines[$0.app]?.max() }.max() ?? 1
        let ids = rows.map(\.id)
        let byID = Dictionary(rows.flatMap { [$0] + $0.processes }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = Binding<Row.ID?>(
            get: {
                // Derived from `selection`, so a pick in the inspector, a search that hides the app, or a Quit shows
                // here: the selected process's row (by pid and start time), else the selected app's row.
                guard let app = selection.app else { return nil }
                guard let p = selection.process else { return app.key }
                // A collapsed app has no process rows; its process's id still selects no row in view.
                let processes = isExpanded(app) ? rows.first { $0.app == app }?.processes
                    : ranking.first { $0.app == app }.map(Self.processRows)
                return processes?.first { $0.process?.pid == p.pid && $0.process?.startTime == p.startTime }?.id ?? app.key
            },
            set: { id in
                // The idle row is a button, not a selection.
                guard id != Row.idleID else { return }
                let row = id.flatMap { byID[$0] }
                if row?.app != selection.app { _fromTable.wrappedValue = true }
                // App first: changing the app clears the process.
                selection.app = row?.app
                selection.process = row?.process
            })

        ScrollViewReader { proxy in
            Table(of: Row.self, selection: selected, sortOrder: _sortOrder.projectedValue, columnCustomization: _columns.projectedValue) {
                TableColumn("App", value: \.name) { row in
                    if row.id == Row.idleID {
                        idleToggle(idle.count)
                    } else if let process = row.process {
                        linked(HStack {
                            Text("\(row.name) (\(String(process.pid)))")
                            if process.exited {
                                Spacer()
                                Text("Exited").font(.caption)
                            }
                        }
                        // Under the app's name: past `AppLabel`'s dot (12), icon (16) and gaps, less the 13 pt the
                        // table indents a child row (measured).
                        .padding(.leading, 12 + 16 + 2 * Layout.gap - 13)
                        .foregroundStyle(process.exited ? .tertiary : .secondary), row, .leading)
                    } else {
                        linked(AppLabel(app: row.app, color: colors[row.app], history: history, pinned: selection.isPinned(row.app), detail: details[row.app.key]),
                               row, .leading)
                    }
                }
                .width(min: 140)
                .customizationID("app")
                .disabledCustomizationBehavior(.visibility)
                TableColumn("Average", value: \.average) { row in
                    if row.id != Row.idleID { linked(Text(metric.format(row.average)).monospacedDigit(), row, .trailing) }
                }
                .width(min: 80, ideal: 88, max: 110)
                .alignment(.trailing)
                .customizationID("average")
                TableColumn("Peak", value: \.peak) { row in
                    if row.id != Row.idleID { linked(Text(metric.format(row.peak)).monospacedDigit(), row, .trailing) }
                }
                .width(min: 80, ideal: 88, max: 110)
                .alignment(.trailing)
                .customizationID("peak")
                if let shareTotal {
                    TableColumn("Share", value: \.average) { row in
                        if row.id != Row.idleID {
                            linked(Text((shareTotal > 0 ? row.average / shareTotal : 0).formatted(.percent.precision(.fractionLength(1))))
                                .monospacedDigit(), row, .trailing)
                        }
                    }
                    .width(min: 64, ideal: 72, max: 90)
                    .alignment(.trailing)
                    .customizationID("share")
                }
                TableColumn("Trend") { row in
                    if row.process == nil, row.id != Row.idleID, let values = sparklines[row.app] {
                        linked(Sparkline(values: values, color: colors[row.app] ?? .secondary, top: top,
                                         threshold: alerts.rules.forApp(row.app.key).level(of: metric)), row, .leading)
                            .onHover { inside in _spark.wrappedValue = inside ? (row.app, Self.pointerInWindow()) : nil }
                            .accessibilityValue(sparkCard(row.app).map { $0.summary } ?? "")
                    }
                }
                .width(min: 60, ideal: 80, max: 120)
                .customizationID("trend")
                TableColumn("PID", value: \.pidOrder) { row in
                    if row.id != Row.idleID { shared(row.pid.map(String.init), row, .trailing) }
                }
                .width(min: 48, ideal: 60, max: 80)
                .alignment(.trailing)
                .customizationID("pid")
                .defaultVisibility(.hidden)
                TableColumn("User", value: \.userOrder) { row in
                    if row.id != Row.idleID { shared(row.user, row, .leading) }
                }
                .width(min: 60, ideal: 90, max: 140)
                .customizationID("user")
                .defaultVisibility(.hidden)
                TableColumn("Pin") { row in
                    if row.process == nil, row.id != Row.idleID {
                        linked(PinButton(app: row.app, name: row.name, selection: selection).labelStyle(.iconOnly).buttonStyle(.borderless), row, .center)
                    }
                }
                .width(36)
                .customizationID("pin")
            } rows: {
                ForEach(rows) { app in
                    DisclosureTableRow(app, isExpanded: expansion(app)) {
                        ForEach(app.processes) { TableRow($0) }
                    }
                }
                if !idle.isEmpty { TableRow(Row.idle) }
            }
            // Double-click or Return opens the inspector on the row.
            .contextMenu(forSelectionType: Row.ID.self) { ids in
                Group {
                    if let row = ids.first.flatMap({ byID[$0] }), row.id != Row.idleID {
                        // Actions on the row, then Copy and Show in Inspector.
                        if row.process == nil {
                            PinButton(app: row.app, name: row.name, selection: selection)
                            Menu("Colour", systemImage: "paintpalette") { AppColorPicker(app: row.app, history: history) }
                                .help("Choose the colour that shows \(row.name)")
                            if row.app.key.hasPrefix("/") {
                                ShowInFinderButton(path: row.app.key, help: "Show \(row.name) in Finder")
                            }
                        }
                        QuitButtons(app: row.app, process: row.process, name: row.name)
                        Divider()
                        if let pid = row.pid {
                            Button("Copy PID", systemImage: "doc.on.doc") { Pasteboard.copy(String(pid)) }
                                .help("Copy the process ID \(String(pid))")
                        }
                        Button("Show in Inspector", systemImage: "sidebar.trailing") {
                            selection.app = row.app
                            selection.process = row.process
                            selection.inspectorShown = true
                        }
                        .help("Show \(row.name) in the inspector")
                    }
                }
                    .labelStyle(.titleAndIcon)
            } primaryAction: { ids in
                guard let id = ids.first, id != Row.idleID else { return }
                selection.inspectorShown = true
            }
            // A hard edge under the header: the soft one blurred into the gap above it.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onHover { inside in _held.wrappedValue = inside && live ? Self.positions(sorted) : nil }
            // Back in Live, an old order must not hold before the pointer comes back.
            // Edit > Copy (⌘C): the selected row as it reads, "Safari" or "Safari Web Content (812)" (N3).
            .copyable(selected.wrappedValue.flatMap { byID[$0] }.map { row in [row.process.map { "\(row.name) (\(String($0.pid)))" } ?? row.name] } ?? [])
            .onChange(of: live) { _held.wrappedValue = nil }
            .onChange(of: _columns.wrappedValue) { _, columns in
                UserDefaults.standard.set(Self.hideable.filter { columns[visibility: $0] == .hidden }, forKey: Self.hiddenKey)
                UserDefaults.standard.set(Self.optional.filter { columns[visibility: $0] == .visible }, forKey: Self.shownKey)
            }
            // A sort picked while the order holds applies at once, and holds in turn.
            .onChange(of: _sortOrder.wrappedValue) { _, order in
                if _held.wrappedValue != nil { _held.wrappedValue = Self.positions(self.rows(sortedBy: order, idle: idle)) }
            }
            // Rows move only for a user action: a sort, a pin, opening an app, the idle row. Live launches, quits
            // and ticks change them with no animation (D67).
            .animation(Motion.smooth(0.25), value: UserChange(
                sort: _sortOrder.wrappedValue,
                pinned: selection.pinned, expanded: _expanded.wrappedValue, idle: _showIdle.wrappedValue))
            .animation(_afterQuiet.wrappedValue ? Motion.smooth(0.25) : nil, value: ids)
            .onChange(of: history.hideQuietSystem) {
                _quietReset.wrappedValue?.cancel()
                _afterQuiet.wrappedValue = true
                _quietReset.wrappedValue = Task {
                    guard (try? await Task.sleep(for: .seconds(10))) != nil else { return }
                    _afterQuiet.wrappedValue = false
                }
            }
            .onChange(of: ids) {
                _afterQuiet.wrappedValue = false
                scrollToPending(proxy, rows: byID, selected: selected.wrappedValue)
            }
            // Sorting again can move the selected row out of view.
            .onChange(of: held == nil) { _, sorting in
                if sorting, let id = selected.wrappedValue { Task { scroll(proxy, to: id) } }
            }
            // An app revealed from Alerts, Calendar, a preview or the inspector comes into view.
            .onChange(of: selection.app) {
                _scrollReset.wrappedValue?.cancel()
                _pendingScroll.wrappedValue = !_fromTable.wrappedValue && selection.app != nil
                _fromTable.wrappedValue = false
                guard _pendingScroll.wrappedValue else { return }
                scrollToPending(proxy, rows: byID, selected: selected.wrappedValue)
                // The row may come with a reload; a reveal that finds none in 5 s is dropped.
                _scrollReset.wrappedValue = Task {
                    guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                    _pendingScroll.wrappedValue = false
                }
            }
            .task(id: _spark.wrappedValue?.app) {
                _sparkShown.wrappedValue = nil
                guard let app = _spark.wrappedValue?.app, (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
                _sparkShown.wrappedValue = app.key
            }
            .previewBeside(_spark.wrappedValue.flatMap { $0.app.key == _sparkShown.wrappedValue ? $0.point : nil }, inWindow: true) {
                if let app = _spark.wrappedValue?.app { sparkCard(app) }
            }
            .overlay(alignment: .top) {
                if held != nil {
                    Label("Sorting paused", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, Layout.padding)
                        .padding(.vertical, Layout.gap)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, Layout.inset)
                        .allowsHitTesting(false)
                }
            }
            // A search that matches no app (S7), shown or idle.
            .overlay {
                if !selection.search.isEmpty && rows.isEmpty && idle.isEmpty {
                    ContentUnavailableView.search(text: selection.search)
                }
            }
        }
    }

    /// The user's row changes: each animates the rows it moves, adds or removes.
    private struct UserChange: Equatable {
        let sort: [KeyPathComparator<Row>]
        let pinned: [AppKey]
        let expanded: Set<Row.ID>
        let idle: Bool
    }

    /// A short glide, or a jump with Reduce Motion or Low Power Mode.
    private func scroll(_ proxy: ScrollViewProxy, to id: Row.ID) {
        withAnimation(Motion.smooth(0.3)) { proxy.scrollTo(id) }
    }

    private func scrollToPending(_ proxy: ScrollViewProxy, rows: [Row.ID: Row], selected: Row.ID?) {
        guard _pendingScroll.wrappedValue, let id = selected, rows[id] != nil else { return }
        _pendingScroll.wrappedValue = false
        scroll(proxy, to: id)
    }

    /// The pointer in window points from the top left: a table cell cannot name the table's space.
    private static func pointerInWindow() -> CGPoint {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return .zero }
        let p = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return CGPoint(x: p.x, y: view.bounds.height - p.y)
    }

    /// The Trend preview: now, average and peak, the app's line with its alert level, its three busiest processes.
    private func sparkCard(_ app: AppKey) -> PreviewCard<Sparkline>? {
        guard let rank = ranking.first(where: { $0.app == app }), let values = sparklines[app] else { return nil }
        let top = values.max() ?? 1
        return PreviewCard(size: .large, title: app.name, span: ["\(metric.label) over \(history.range.label)"],
                           stats: [.init(label: "Now", value: metric.format(values.last ?? 0)),
                                   .init(label: "Average", value: metric.format(rank.average)),
                                   .init(label: "Peak", value: metric.format(rank.peak))],
                           sections: [.init(heading: "Busiest processes",
                                            rows: rank.processes.sorted { $0.average > $1.average }.prefix(3)
                                                .map { .init(label: "\($0.name) (\($0.pid))", value: metric.format($0.average)) })]) {
            Sparkline(values: values, color: colors[app] ?? .secondary, top: top,
                      threshold: alerts.rules.forApp(app.key).level(of: metric), height: 96)
        }
    }

    /// Apps of the ranking in `order`, each expanded app with its processes; `idle` apps only when shown or selected.
    /// A collapsed app has no process rows: the table keeps state for each child row, and with it each reload's rows.
    private func rows(sortedBy order: [KeyPathComparator<Row>], idle: Set<AppKey>) -> [Row] {
        ranking.filter { _showIdle.wrappedValue || !idle.contains($0.app) || $0.app == selection.app }.map { app in
            let users = Set(app.processes.map { Self.userName($0.uid) })
            return Row(id: app.app.key, name: app.app.name, app: app.app, process: nil, average: app.average, peak: app.peak,
                       pid: app.processes.count == 1 ? app.processes[0].pid : nil, user: users.count == 1 ? users.first : nil,
                       processes: isExpanded(app.app) ? Self.processRows(app).sorted(using: order) : [])
        }.sorted(using: order)
    }

    /// Average and peak both read 0 in this metric.
    private func isIdle(_ app: AppRank) -> Bool {
        let zero = metric.format(0)
        return metric.format(app.average) == zero && metric.format(app.peak) == zero
    }

    private func idleToggle(_ count: Int) -> some View {
        let shown = _showIdle.wrappedValue
        let label = "\(count) idle app\(count == 1 ? "" : "s")"
        return Button(label, systemImage: shown ? "chevron.down" : "chevron.right") { _showIdle.wrappedValue.toggle() }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(shown ? "Hide" : "Show") \(label)")
            .help(shown ? "Hide idle apps" : "Show idle apps")
    }

    /// A process's value, or an app's when all its processes share it; blank with a hint when they differ.
    private func shared(_ value: String?, _ row: Row, _ alignment: Alignment) -> some View {
        // One labelled element: a blank cell has no text element to carry the hint.
        linked(Text(value ?? "").monospacedDigit(), row, alignment)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value ?? "Several")
            .accessibilityAddTraits(.isStaticText)
            .help(value == nil ? "Several" : "")
    }

    /// A cell that reports its row's app under the pointer, over the cell's full width.
    private func linked(_ content: some View, _ row: Row, _ alignment: Alignment) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(.rect)
            .onHover { hover(row.app.key, $0) }
    }

    /// Each row's position, apps and processes, in display order.
    private static func positions(_ rows: [Row]) -> [Row.ID: Int] {
        Dictionary(rows.flatMap { [$0] + $0.processes }.enumerated().map { ($1.id, $0) }) { first, _ in first }
    }

    /// `rows` in the held positions; rows that came after the order was held go last, in sort order.
    private static func holding(_ rows: [Row], at positions: [Row.ID: Int]) -> [Row] {
        rows.enumerated()
            .sorted { (positions[$0.element.id] ?? .max, $0.offset) < (positions[$1.element.id] ?? .max, $1.offset) }
            .map { var row = $0.element; row.processes = holding(row.processes, at: positions); return row }
    }

    /// An app found by search only through its processes opens to show them.
    private func isExpanded(_ app: AppKey) -> Bool {
        (!selection.search.isEmpty && !AppSearch.matches(app, selection.search)) || _expanded.wrappedValue.contains(app.key)
    }

    private func expansion(_ app: Row) -> Binding<Bool> {
        Binding(
            get: { isExpanded(app.app) },
            set: { open in
                if open { _expanded.wrappedValue.insert(app.id) } else { _expanded.wrappedValue.remove(app.id) }
            })
    }

    /// Live rows have no DB id (processID 0) and a pid can repeat inside the Live window, so a repeat
    /// gets its occurrence number; other ids stay stable across reloads.
    private static func processRows(_ app: AppRank) -> [Row] {
        var seen: [String: Int] = [:]
        return app.processes.map { p in
            let base = "\(app.app.key)/\(p.processID)/\(p.pid)"
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return Row(id: n == 1 ? base : "\(base)#\(n)", name: p.name, app: app.app, process: p,
                       average: p.average, peak: p.peak, pid: p.pid, user: userName(p.uid), processes: [])
        }
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let app: AppKey
        /// nil for an app row.
        let process: ProcessRank?
        let average: Double
        let peak: Double
        /// The process's, or the app's when all its processes share one; nil when they differ. A user is "" when unknown.
        let pid: Int32?
        let user: String?
        var processes: [Row]

        var pidOrder: Int32 { pid ?? -1 }
        var userOrder: String { user ?? "" }

        static let idleID = "\u{0}idle"
        /// The last row: shows or hides the idle apps.
        static let idle = Row(id: idleID, name: "", app: AppKey(key: "", name: ""), process: nil, average: 0, peak: 0,
                              pid: nil, user: "", processes: [])
    }
}

/// Equal inputs skip the body: in Live the chart redraws every second, but the ranking and the sparklines change every 5 s.
extension AppTable: Equatable {
    nonisolated static func == (a: AppTable, b: AppTable) -> Bool {
        (a.ranking, a.colors, a.metric, a.sparklines, a.shareTotal, a.live)
            == (b.ranking, b.colors, b.metric, b.sparklines, b.shareTotal, b.live)
    }
}
