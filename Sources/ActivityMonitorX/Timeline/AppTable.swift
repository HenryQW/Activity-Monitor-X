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
    private let _expanded = State<Set<Row.ID>>(initialValue: [])
    private let _sortOrder = State(initialValue: [KeyPathComparator(\Row.average, order: .reverse)])
    /// Row positions (apps and processes) while the order holds; nil while the table sorts.
    private let _held = State<[Row.ID: Int]?>(initialValue: nil)
    private let _showIdle = State(initialValue: false)
    @SceneStorage("appTableColumns") private var columns = TableColumnCustomization<Row>()

    var body: some View {
        let sorted = rows(sortedBy: _sortOrder.wrappedValue)
        let held = live ? _held.wrappedValue : nil
        let rows = held.map { Self.holding(sorted, at: $0) } ?? sorted
        let idle = ranking.count(where: isIdle)
        let details = AppKey.details(for: ranking.map(\.app))
        // One y scale per metric: 0 to the largest value in view, so rows compare with each other.
        let top = ranking.compactMap { sparklines[$0.app]?.max() }.max() ?? 1
        let byID = Dictionary(rows.flatMap { [$0] + $0.processes }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = Binding<Row.ID?>(
            get: {
                // Derived from `selection`, so a pick in the inspector, a search that hides the app, or a Quit shows
                // here: the selected process's row (by pid and start time), else the selected app's row.
                guard let app = selection.app else { return nil }
                guard let p = selection.process else { return app.key }
                return rows.first { $0.app == app }?.processes
                    .first { $0.process?.pid == p.pid && $0.process?.startTime == p.startTime }?.id ?? app.key
            },
            set: { id in
                // The idle row is a button, not a selection.
                guard id != Row.idleID else { return }
                let row = id.flatMap { byID[$0] }
                // App first: changing the app clears the process.
                selection.app = row?.app
                selection.process = row?.process
            })

        ScrollViewReader { proxy in
            Table(of: Row.self, selection: selected, sortOrder: _sortOrder.projectedValue, columnCustomization: $columns) {
                TableColumn("App", value: \.name) { row in
                    if row.id == Row.idleID {
                        idleToggle(idle)
                    } else if let process = row.process {
                        linked(HStack {
                            Text("\(row.name) (\(String(process.pid)))")
                            if process.exited {
                                Spacer()
                                Text("Exited").font(.caption)
                            }
                        }
                        .foregroundStyle(process.exited ? .tertiary : .secondary), row, .leading)
                    } else {
                        linked(AppLabel(app: row.app, color: colors[row.app], pinned: selection.isPinned(row.app), detail: details[row.app.key]),
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
                        linked(Sparkline(values: values, color: colors[row.app] ?? .secondary, top: top), row, .leading)
                    }
                }
                .width(min: 60, ideal: 80, max: 120)
                .customizationID("trend")
                TableColumn("Pin") { row in
                    if row.process == nil, row.id != Row.idleID {
                        linked(pinButton(row.app).labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityLabel(selection.isPinned(row.app) ? "Unpin \(row.name)" : "Pin \(row.name)"), row, .center)
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
                if idle > 0 { TableRow(Row.idle) }
            }
            // Double-click or Return opens the inspector on the row.
            .contextMenu(forSelectionType: Row.ID.self) { ids in
                if let row = ids.first.flatMap({ byID[$0] }), row.id != Row.idleID {
                    Button("Show in Inspector", systemImage: "sidebar.trailing") {
                        selection.app = row.app
                        selection.process = row.process
                        selection.inspectorShown = true
                    }
                    .help("Show \(row.name) in the inspector")
                    if row.process == nil {
                        pinButton(row.app)
                        Menu("Colour") { AppColorPicker(app: row.app, history: history) }
                            .help("Choose the app's colour")
                    }
                }
            } primaryAction: { ids in
                guard let id = ids.first, id != Row.idleID else { return }
                selection.inspectorShown = true
            }
            // A hard edge under the header: the soft one blurred into the gap above it.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onHover { inside in _held.wrappedValue = inside && live ? Self.positions(sorted) : nil }
            // Back in Live, an old order must not hold before the pointer comes back.
            .onChange(of: live) { _held.wrappedValue = nil }
            // A sort picked while the order holds applies at once, and holds in turn.
            .onChange(of: _sortOrder.wrappedValue) { _, order in
                if _held.wrappedValue != nil { _held.wrappedValue = Self.positions(self.rows(sortedBy: order)) }
            }
            // Sorting again can move the selected row out of view.
            .onChange(of: held == nil) { _, sorting in
                if sorting, let id = selected.wrappedValue { Task { proxy.scrollTo(id) } }
            }
            .overlay(alignment: .top) {
                if held != nil {
                    Label("Sorting paused", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Apps of the ranking in `order`, each with its processes; idle apps only when shown or selected.
    private func rows(sortedBy order: [KeyPathComparator<Row>]) -> [Row] {
        ranking.filter { _showIdle.wrappedValue || !isIdle($0) || $0.app == selection.app }.map { app in
            Row(id: app.app.key, name: app.app.name, app: app.app, process: nil, average: app.average, peak: app.peak,
                processes: Self.processRows(app).sorted(using: order))
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

    private func pinButton(_ app: AppKey) -> some View {
        let pinned = selection.isPinned(app)
        return Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.fill" : "pin") { selection.togglePin(app) }
            .help(pinned ? "Unpin \(app.name)" : "Pin \(app.name) to the sidebar")
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
    private func expansion(_ app: Row) -> Binding<Bool> {
        let found = !selection.search.isEmpty && !AppSearch.matches(app.app, selection.search)
        return Binding(
            get: { found || _expanded.wrappedValue.contains(app.id) },
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
                       average: p.average, peak: p.peak, processes: [])
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
        var processes: [Row]

        static let idleID = "\u{0}idle"
        /// The last row: shows or hides the idle apps.
        static let idle = Row(id: idleID, name: "", app: AppKey(key: "", name: ""), process: nil, average: 0, peak: 0, processes: [])
    }
}

/// Equal inputs skip the body: in Live the chart redraws every second, but the ranking and the sparklines change every 5 s.
extension AppTable: Equatable {
    nonisolated static func == (a: AppTable, b: AppTable) -> Bool {
        (a.ranking, a.colors, a.metric, a.sparklines, a.shareTotal, a.live)
            == (b.ranking, b.colors, b.metric, b.sparklines, b.shareTotal, b.live)
    }
}

/// One line, no axes; the y scale is shared by every row (0 to `top`).
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let top: Double

    var body: some View {
        SparklineShape(values: values, top: top, slots: values.count)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            .frame(height: 18)
            .accessibilityHidden(true)
    }
}
