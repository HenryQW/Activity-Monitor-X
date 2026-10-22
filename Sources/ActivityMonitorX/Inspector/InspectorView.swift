import AMXCore
import AppKit
import Charts
import SwiftUI

/// The selected app for the range (or span): its series, peak process, alerts and processes, with Pin, Quit and
/// Force Quit; with no app selected, a summary of the range. Both are a bento of default `GroupBox` cards (D32).
struct InspectorView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    /// The app whose full process list is shown; another app starts short again.
    private let _showAllOf = State<String?>(initialValue: nil)
    /// The pane's width, for `pair`.
    private let _width = State(initialValue: 0.0)
    /// The least pane width that puts About beside Peak Process: under it the text column gets too narrow.
    private static let pairFrom = 340.0

    var body: some View {
        let isLive = history.range == .live
        let load = isLive ? live.state : history.state
        if let app = selection.app {
            if load == .loading {
                ProgressView()
            } else if load == .ready, let rank = isLive ? live.rank(of: app) : history.rank(of: app) {
                details(rank, series: isLive ? live.series(of: app) : history.series(of: app),
                        events: isLive ? [] : history.events.filter { event in
                            event.app?.key == app.key && history.span.map { $0.contains(event.ts) } ?? true
                        })
            } else {
                ContentUnavailableView(app.name, systemImage: "app.dashed", description: Text("No data in this range."))
            }
        } else if load == .ready {
            summary(isLive: isLive)
        } else if load == .loading {
            ProgressView()
        } else {
            ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("No data in this range."))
        }
    }

    /// With no app selected, the range (or span) at a glance: the total, the top apps and the alerts, so
    /// "what slows my Mac" needs no click. A click on an app, or on an alert that names one, selects it.
    private func summary(isLive: Bool) -> some View {
        let metric = history.metric
        let ranking = isLive ? live.ranking : history.ranking
        let points = isLive ? live.stacked : history.stacked
        let colors = AppPalette.colors(for: points)
        // The table's order and search; the totals stay those of every app, as the chart's do.
        let top = AppSearch.filter(ranking, query: selection.search).prefix(3)
        let details = AppKey.details(for: top.map(\.app))
        let span = isLive ? nil : history.span
        let events = history.events.filter { event in (event.level ?? 0) >= 1 && span.map { $0.contains(event.ts) } ?? true }
        return cards {
            GroupBox {
                Text(history.scope?.name ?? "All Apps").font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
            }
            tiles {
                tile("Average", metric.format(ranking.reduce(0) { $0 + $1.average }),
                     help: "The sum of the listed apps' averages: hidden quiet system processes are not counted.")
                tile("Peak", metric.format(AppSeries.peakTotal(points, bucket: history.range.chartBucket, in: span)),
                     help: "The highest bucket total in the chart, every process counted.")
            }
            card("Top Apps") {
                if top.isEmpty {
                    Text(selection.search.isEmpty ? "No apps" : "No app matches the search").foregroundStyle(.secondary)
                }
                ForEach(top) { rank in
                    Button { selection.app = rank.app } label: {
                        LabeledContent {
                            Text(metric.format(rank.average)).monospacedDigit()
                        } label: {
                            AppLabel(app: rank.app, color: colors[rank.app], pinned: selection.isPinned(rank.app),
                                     detail: details[rank.app.key])
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Live loads no events.
            if !isLive {
                card(events.isEmpty ? "Alerts" : "Alerts (\(events.count.formatted()))") {
                    if events.isEmpty {
                        Text("No alerts").foregroundStyle(.secondary)
                    }
                    // The latest five; the chart's markers hold the rest.
                    ForEach(Array(events.suffix(5).reversed().enumerated()), id: \.offset) { _, event in
                        if let app = event.app {
                            Button { selection.app = app } label: { EventRow(event: event).contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                        } else {
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
    }

    private func details(_ rank: AppRank, series: [SeriesPoint], events: [EventMark]) -> some View {
        let metric = history.metric
        // A pinned app's view colours its app from the app's own series; every other view uses the top-5 mapping.
        let pinned: Bool = if case .pinned(let focus) = selection.sidebar { focus.key == rank.app.key } else { false }
        let color = AppPalette.colors(for: pinned ? series : history.range == .live ? live.stacked : history.stacked)[rank.app] ?? .secondary
        let detail = AppKey.details(for: (history.range == .live ? live.ranking : history.ranking).map(\.app) + [rank.app])[rank.app.key]
        let running = rank.processes.filter { !$0.exited }
        let exited = rank.processes.filter(\.exited)
        let runningRows = AppRank.byName(running)
        // A long-gone helper never hides a running process: only the exited rows are cut, to the top 20 by average.
        let exitedRows = AppRank.byName(exited)
        let shownExited = exitedRows.prefix(_showAllOf.wrappedValue == rank.app.key ? .max : 20)
        let selected = Binding<ProcKey?>(
            get: { selection.process.map(ProcKey.init) },
            set: { key in selection.process = rank.processes.first { ProcKey($0) == key } })
        // One List, one scroll: the cards are its first rows (not selectable), the processes the rows after them, so a
        // click selects a process and the arrow keys move through the processes only.
        return List(selection: selected) {
            Group {
                GroupBox {
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Image(nsImage: AppIcon.image(for: rank.app)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rank.app.name).font(.title3.bold()).help(rank.app.key)
                            // The bundle path, or what tells this app from another app of its name in the range.
                            if let path = rank.app.key.hasPrefix("/") ? (rank.app.key as NSString).abbreviatingWithTildeInPath : detail {
                                Text(path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(rank.app.key)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                tiles {
                    tile("Average", metric.format(rank.average), help: "The app's average in the range, every process counted.")
                    tile("Peak", metric.format(rank.peak), help: "The app's highest value in the range.")
                }
                card(metric.label) {
                    let drawn = AppSeries.closed(series, bucket: history.range.chartBucket)
                    Chart(drawn.indices, id: \.self) { i in
                        AreaMark(x: .value("Time", Date(timeIntervalSince1970: drawn[i].bucket)),
                                 y: .value(metric.label, drawn[i].value))
                            .foregroundStyle(color.opacity(0.6))
                    }
                    .chartXAxis {
                        let (unit, count) = Self.xStride(series)
                        AxisMarks(values: .stride(by: unit, count: count))
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) { Text(metric.axisLabel(v)) }
                            }
                        }
                    }
                    .frame(height: 110)
                }
                // Side by side only where the pane is wide enough: the About text wraps badly in half of a narrow pane.
                let pair = _width.wrappedValue >= Self.pairFrom
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
                pair {
                    if let entry = history.glossaryEntry(app: rank.app, process: selection.process) {
                        card("About") {
                            Text(entry.title).font(.headline)
                            if let vendor = entry.vendor { Text(vendor).foregroundStyle(.secondary) }
                            Text(entry.description)
                            if entry.expectedHigh == true {
                                Text("High use is normal for this process.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let peak = rank.processes.max(by: { $0.peak < $1.peak }) {
                        card("Peak Process") {
                            Text("\(peak.name) (\(String(peak.pid)))")
                            Text(metric.format(peak.peak)).font(.title2).monospacedDigit()
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                card(events.isEmpty ? "Alerts" : "Alerts (\(events.count.formatted()))") {
                    if events.isEmpty {
                        Text("No alerts").foregroundStyle(.secondary)
                    }
                    ForEach(events.indices, id: \.self) { EventRow(event: events[$0]) }
                }
            }
            .selectionDisabled()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            if !running.isEmpty {
                Section("Running (\(running.count.formatted()))") {
                    // By name: the first process of a name changes as averages shift (each second in Live), which would close an open row.
                    ForEach(runningRows, id: \.[0].name) { processRows($0, of: rank.app) }
                }
            }
            if !exited.isEmpty {
                Section("Exited (\(exited.count.formatted()))") {
                    ForEach(shownExited, id: \.[0].name) { processRows($0, of: rank.app) }
                    if shownExited.count < exitedRows.count {
                        Button("Show All \(exited.count.formatted())") { _showAllOf.wrappedValue = rank.app.key }
                            .buttonStyle(.link)
                            .help("Show all exited processes")
                    }
                }
            }
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { _width.wrappedValue = $0 }
        // A solid bar, apart from the cards, keeps the destructive buttons away from the app's name.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    let isPinned = selection.isPinned(rank.app)
                    Button(isPinned ? "Unpin" : "Pin") { selection.togglePin(rank.app) }
                        .help(isPinned ? "Unpin \(rank.app.name)" : "Pin \(rank.app.name) to the sidebar")
                    if let process = selection.signallable {
                        Button("Quit") { selection.signalRequest = SignalRequest(process: process, signal: SIGTERM) }
                            .help("Ask \(process.name) to quit")
                        Button("Force Quit") { selection.signalRequest = SignalRequest(process: process, signal: SIGKILL) }
                            .help("Stop \(process.name) immediately. Unsaved changes are lost.")
                    } else if let process = selection.process {
                        Text(process.exited ? "Process has exited" : "Cannot quit this process").foregroundStyle(.secondary)
                    } else if case let apps = Self.running(rank.app), !apps.isEmpty {
                        Button("Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGTERM) }
                            .help("Ask \(rank.app.name) to quit")
                        Button("Force Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGKILL) }
                            .help("Stop \(rank.app.name) immediately. Unsaved changes are lost.")
                    } else if rank.processes.allSatisfy(\.exited) {
                        Text("No running processes").foregroundStyle(.secondary)
                    } else {
                        // A bare executable name (zsh, node) can stand for other users' and unrelated processes.
                        Text("Select a process to quit").foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// The summary's bento: cards in one scrolling column.
    private func cards(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            VStack(spacing: 10) { content() }.padding(12)
        }
    }

    /// A full-width card: its title, then its rows.
    private func card(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) { content() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// A small tile: a title and one value.
    private func tile(_ title: String, _ value: String, help: String) -> some View {
        card(title) { Text(value).font(.title2).monospacedDigit() }.help(help)
    }

    /// Two small tiles side by side at every pane width, one height.
    private func tiles(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) { content() }.fixedSize(horizontal: false, vertical: true)
    }

    /// A whole-minute, hour or day stride for about three x labels: more truncate at the inspector's 240 pt, and
    /// `.automatic(desiredCount:)` does not lower the count of a date axis (measured).
    private static func xStride(_ series: [SeriesPoint]) -> (Calendar.Component, Int) {
        let step = ((series.last?.bucket ?? 0) - (series.first?.bucket ?? 0)) / 3
        if step < 3600 { return (.minute, [1, 2, 5, 10, 15, 30].first { Double($0 * 60) >= step } ?? 60) }
        if step < 86_400 { return (.hour, [1, 2, 3, 6, 12].first { Double($0 * 3600) >= step } ?? 24) }
        return (.day, Int((step / 86_400).rounded(.up)))
    }

    /// One row per process, or one collapsed row for several of one name ("disclaimer × 14").
    @ViewBuilder
    private func processRows(_ group: [ProcessRank], of app: AppKey) -> some View {
        if group.count == 1 {
            processRow(group[0], named: group[0].name != app.name)
        } else {
            DisclosureGroup {
                ForEach(group, id: \.key) { processRow($0, named: false) }
            } label: {
                LabeledContent("\(group[0].name) × \(group.count.formatted())",
                               value: history.metric.format(group.reduce(0) { $0 + $1.average }))
                    .monospacedDigit()
            }
            .foregroundStyle(group[0].exited ? .secondary : .primary)
        }
    }

    /// "PID 91539  1.1 %": the name only when it is not the app's; an exited process shows when it was last seen.
    private func processRow(_ p: ProcessRank, named: Bool) -> some View {
        let pid = named ? "\(p.name) (\(String(p.pid)))" : "PID \(String(p.pid))"
        let format: Date.FormatStyle = history.range.seconds >= 86_400
            ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute()
        return LabeledContent(p.exited ? "\(pid) · \(Date(timeIntervalSince1970: p.lastSeen).formatted(format))" : pid,
                              value: history.metric.format(p.average))
            .monospacedDigit()
            .foregroundStyle(p.exited ? .secondary : .primary)
            .tag(ProcKey(p))
    }

    /// The running copies of an app bundle; none for a bare executable name.
    private static func running(_ app: AppKey) -> [NSRunningApplication] {
        guard app.key.hasSuffix(".app") else { return [] }
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == app.key }
    }
}

/// An event's message with its date and time below.
private struct EventRow: View {
    let event: EventMark

    var body: some View {
        VStack(alignment: .leading) {
            Text(event.message)
            Text(Date(timeIntervalSince1970: event.ts).formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ProcKey: Hashable {
    let pid: Int32
    let startTime: Double

    init(_ p: ProcessRank) { (pid, startTime) = (p.pid, p.startTime) }
}

private extension ProcessRank {
    var key: ProcKey { ProcKey(self) }
}
