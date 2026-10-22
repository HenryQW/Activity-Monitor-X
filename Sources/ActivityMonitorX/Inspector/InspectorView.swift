import AMXCore
import AppKit
import Charts
import SwiftUI

/// The selected app for the range (or span): its series, peak process, alerts and processes, with Pin, Quit and
/// Force Quit; with no app selected, a summary of the range. Both are a grouped `Form`, one section per topic, as in the
/// system's own panes. An app's inspector has three pills above its content: Overview shows the form, Processes the
/// process list, Files the open files and sockets. The pill is kept per window, and selecting a process in the table
/// switches it to Processes.
struct InspectorView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    @SceneStorage("inspectorTab") private var tab = Tab.overview
    private enum Tab: String { case overview = "Overview", processes = "Processes", files = "Files" }
    /// The app whose full process list is shown; another app starts short again.
    private let _showAllOf = State<String?>(initialValue: nil)
    private let _rulesShown = State(initialValue: false)
    private let _files = State(initialValue: OpenFilesModel())

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

    /// With no app selected, the range (or span) at a glance: system health, the top apps, the biggest changes and the
    /// alert counts, so "what slows my Mac" needs no click. A click on an app selects it.
    private func summary(isLive: Bool) -> some View {
        let metric = history.metric
        let ranking = isLive ? live.ranking : history.ranking
        let points = isLive ? live.stacked : history.stacked
        let colors = AppPalette.colors(for: points, chosen: history.appColors)
        // The table's order and search; the totals stay those of every app, as the chart's do.
        let top = AppSearch.filter(ranking, query: selection.search).prefix(3)
        let details = AppKey.details(for: top.map(\.app))
        let span = isLive ? nil : history.span
        let events = history.events.filter { event in (event.level ?? 0) >= 1 && span.map { $0.contains(event.ts) } ?? true }
        return Form {
            Section { Text(history.scope?.name ?? "All Apps").font(.title3.bold()) }
            SystemHealthCard(isLive: isLive)
            Section("Top Apps") {
                if top.isEmpty {
                    Text(selection.search.isEmpty ? "No apps" : "No app matches the search").foregroundStyle(.secondary)
                }
                ForEach(top) { rank in
                    Button { selection.app = rank.app } label: {
                        LabeledContent {
                            Text(metric.format(rank.average)).monospacedDigit()
                        } label: {
                            AppLabel(app: rank.app, color: colors[rank.app], history: history, pinned: selection.isPinned(rank.app),
                                     detail: details[rank.app.key])
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Live loads no events, and no range before it.
            if !isLive {
                BiggestChangesCard(colors: colors)
                AlertCountsCard(events: events)
            }
        }
        .formStyle(.grouped)
    }

    private func details(_ rank: AppRank, series: [SeriesPoint], events: [EventMark]) -> some View {
        let metric = history.metric
        // A pinned app's view colours its app from the app's own series; every other view uses the top-5 mapping.
        let pinned: Bool = if case .pinned(let focus) = selection.sidebar { focus.key == rank.app.key } else { false }
        let color = AppPalette.colors(for: pinned ? series : history.range == .live ? live.stacked : history.stacked,
                                      chosen: history.appColors)[rank.app] ?? .secondary
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
        // Overview and Files are grouped Forms; Processes is a List, so a click selects a process and the arrow keys
        // move through the processes. The ZStack keeps the pills and the bottom bar when the pill changes.
        return ZStack {
            if tab == .overview {
                Form {
                    Section {
                        HStack(spacing: 8) {
                            AppColorDot(app: rank.app, history: history, color: color, size: 16)
                            Image(nsImage: AppIcon.image(for: rank.app)).resizable().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.app.name).font(.title3.bold()).lineLimit(1).help(rank.app.key)
                                // The bundle path, or what tells this app from another app of its name in the range.
                                if let path = rank.app.key.hasPrefix("/") ? (rank.app.key as NSString).abbreviatingWithTildeInPath : detail {
                                    Text(path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(rank.app.key)
                                }
                            }
                        }
                        LabeledContent("Average", value: metric.format(rank.average))
                            .monospacedDigit()
                            .help("The app's average in the range, every process counted.")
                        LabeledContent("Peak", value: metric.format(rank.peak))
                            .monospacedDigit()
                            .help("The app's highest value in the range.")
                    }
                    if history.range != .live { UsualCard(rank: rank) }
                    Section(metric.label) {
                        Chart {
                            // One vectorized plot, not a mark per point.
                            AreaPlot(AppSeries.closed(series, bucket: history.range.chartBucket), x: .value("Time", \.date),
                                     y: .value(metric.label, \.value))
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
                    if let entry = history.glossaryEntry(app: rank.app, process: selection.process) {
                        Section("About") {
                            LabeledContent("Name", value: entry.title)
                            if let vendor = entry.vendor { LabeledContent("Vendor", value: vendor) }
                            Text(entry.description)
                            if entry.expectedHigh == true {
                                Text("High use is normal for this process.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let peak = rank.processes.max(by: { $0.peak < $1.peak }) {
                        Section("Peak Process") {
                            LabeledContent("\(peak.name) (\(String(peak.pid)))", value: metric.format(peak.peak)).monospacedDigit()
                        }
                    }
                    if history.range != .live { LaunchHistoryCard(app: rank.app) }
                    Section(events.isEmpty ? "Alerts" : "Alerts (\(events.count.formatted()))") {
                        if events.isEmpty {
                            Text("No alerts").foregroundStyle(.secondary)
                        }
                        ForEach(events.indices, id: \.self) { EventRow(event: events[$0]) }
                        Button("Alert Rules…") { _rulesShown.wrappedValue = true }
                            .help("Mute alerts for \(rank.app.name) or give it its own alert values")
                    }
                }
                .formStyle(.grouped)
            } else if tab == .files {
                Form { OpenFilesRows(model: _files.wrappedValue, processes: running, client: live.client) }
                    .formStyle(.grouped)
            } else {
                List(selection: selected) {
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
            }
        }
        .task(id: tab == .files ? rank.app.key : nil) {
            if tab == .files { await _files.wrappedValue.load(running, client: live.client) }
        }
        .onChange(of: selection.process) { _, process in if process != nil { tab = .processes } }
        .sheet(isPresented: _rulesShown.projectedValue) { AppRulesSheet(app: rank.app) }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach([Tab.overview, .processes, .files], id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("View")
            .help("Show the overview, the processes or the open files")
            .padding(10)
        }
        // A solid bar, apart from the sections, keeps the destructive buttons away from the app's name.
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
                        disabledQuit(process.exited ? "Process has exited" : "Cannot quit this process")
                    } else if case let apps = Self.running(rank.app), !apps.isEmpty {
                        Button("Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGTERM) }
                            .help("Ask \(rank.app.name) to quit")
                        Button("Force Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGKILL) }
                            .help("Stop \(rank.app.name) immediately. Unsaved changes are lost.")
                    } else if rank.processes.allSatisfy(\.exited) {
                        disabledQuit("No running processes")
                    } else {
                        // A bare executable name (zsh, node) can stand for other users' and unrelated processes.
                        disabledQuit("Select a process to quit")
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// A Quit button that cannot act now; the help says why.
    private func disabledQuit(_ reason: String) -> some View {
        Button("Quit") {}.disabled(true).help(reason)
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
        return LabeledContent(p.exited ? "\(pid) · \(Date(timeIntervalSince1970: p.lastSeen).formatted(history.range.timeFormat))" : pid,
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

private extension SeriesPoint {
    /// The bucket's start, for a chart's time axis.
    var date: Date { Date(timeIntervalSince1970: bucket) }
}
