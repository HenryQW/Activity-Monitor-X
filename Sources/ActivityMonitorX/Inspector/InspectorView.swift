import AMXCore
import AppKit
import Charts
import SwiftUI

/// The selected app for the range (or span): its series, peak process, alerts and processes, with a row of actions
/// under its name (Pin, Show in Finder, Alert Rules, Quit); with no app selected, a summary of the range. Both are a grouped `Form`, one section per topic, as in the
/// system's own panes. An app's inspector has three pills above its content: Overview shows the form, Processes the
/// process list, Files the open files and sockets. The pill is kept per window, and selecting a process in the table
/// switches it to Processes.
struct InspectorView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    @SceneStorage("inspectorTab") private var tab = Tab.overview
    private struct Roll: Equatable {
        let app: String
        let span: ClosedRange<Double>?
    }
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
            Section { Text(history.scope?.name ?? "All Apps").font(.title3.bold()).overlayScrollers() }
            SystemHealthCard(isLive: isLive)
            CardSection("Top Apps", summary: top.first.map { Text("\($0.app.name) \(metric.format($0.average))") }) {
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
        // The numbers roll for a change the user made (another app, another span), never for a Live tick.
        let roll = Roll(app: rank.app.key, span: history.span)
        let runningRows = AppRank.byName(running)
        let usual = history.range == .live ? nil : history.usual(of: rank.app)
        // A long-gone helper never hides a running process: only the exited rows are cut, to the top 20 by average.
        let exitedRows = AppRank.byName(exited)
        let shownExited = exitedRows.prefix(_showAllOf.wrappedValue == rank.app.key ? .max : 20)
        let selected = Binding<ProcKey?>(
            get: { selection.process.map(ProcKey.init) },
            set: { key in selection.process = rank.processes.first { ProcKey($0) == key } })
        // Overview and Files are grouped Forms; Processes is a List, so a click selects a process and the arrow keys
        // move through the processes. The ZStack keeps the pills when the pill changes.
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
                        .overlayScrollers()
                        actions(rank)
                        LabeledContent {
                            Text(metric.format(rank.average))
                                .contentTransition(.numericText(value: rank.average))
                                .animation(Motion.smooth(0.25), value: roll)
                        } label: {
                            Text("Average")
                            if let usual { Text(Self.compare(rank.average, usual: usual, metric: metric)) }
                        }
                        .monospacedDigit()
                        .help("The app's average in the range, every process counted.")
                        LabeledContent {
                            Text(metric.format(rank.peak))
                                .contentTransition(.numericText(value: rank.peak))
                                .animation(Motion.smooth(0.25), value: roll)
                        } label: {
                            Text("Peak")
                        }
                        .monospacedDigit()
                        .help("The app's highest value in the range.")
                    } footer: {
                        // Live has no usual value.
                        if history.range != .live {
                            Text(usual == nil ? "Usual needs 2 days of history in the 7 days before the range."
                                 : "Usual: the same hours of day in the 7 days before the range.")
                        }
                    }
                    CardSection(metric.label) {
                        Chart {
                            // One vectorized plot, not a mark per point.
                            AreaPlot(AppSeries.closed(series, bucket: history.range.chartBucket), x: .value("Time", \.date),
                                     y: .value(metric.label, \.value))
                                .foregroundStyle(color.opacity(0.6))
                        }
                        .chartXAxis {
                            let seconds = (series.last?.bucket ?? 0) - (series.first?.bucket ?? 0)
                            let (unit, count) = Self.xStride(seconds: seconds)
                            AxisMarks(values: .stride(by: unit, count: count)) { _ in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel(format: AppTime.axisFormat(seconds: seconds))
                            }
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
                        CardSection("About") {
                            LabeledContent("Name", value: entry.title)
                            if let vendor = entry.vendor { LabeledContent("Vendor", value: vendor) }
                            Text(entry.description)
                            if entry.expectedHigh == true {
                                Text("High use is normal for this process.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let peak = rank.processes.max(by: { $0.peak < $1.peak }) {
                        CardSection("Peak Process") {
                            LabeledContent("\(peak.name) (\(String(peak.pid)))", value: metric.format(peak.peak)).monospacedDigit()
                        }
                    }
                    if history.range != .live { LaunchHistoryCard(app: rank.app, processes: rank.processes, color: color) }
                    CardSection("Alerts", summary: Text(events.count.formatted())) {
                        if events.isEmpty {
                            Text("No alerts").foregroundStyle(.secondary)
                        }
                        ForEach(events.indices, id: \.self) { EventRow(event: events[$0]) }
                    }
                }
                .formStyle(.grouped)
            } else if tab == .files {
                Form { OpenFilesRows(model: _files.wrappedValue, processes: running, client: live.client) }
                    .formStyle(.grouped)
            } else {
                List(selection: selected) {
                    if !running.isEmpty {
                        Section {
                            // By name: the first process of a name changes as averages shift (each second in Live), which would close an open row.
                            ForEach(runningRows, id: \.[0].name) { processRows($0, of: rank.app) }
                        } header: {
                            Text("Running (\(running.count.formatted()))").overlayScrollers()
                        }
                    }
                    if !exited.isEmpty {
                        Section {
                            ForEach(shownExited, id: \.[0].name) { processRows($0, of: rank.app) }
                            if shownExited.count < exitedRows.count {
                                Button("Show All \(exited.count.formatted())") { _showAllOf.wrappedValue = rank.app.key }
                                    .buttonStyle(.link)
                                    .help("Show the list of all exited processes")
                            }
                        } header: {
                            Text("Exited (\(exited.count.formatted()))").overlayScrollers()
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
    }

    /// Pin, Show in Finder, Alert Rules and Quit: one width and one height, icon over title. Quit only asks; its
    /// confirmation offers Force Quit, so no destructive action is one click from the app's name.
    private func actions(_ rank: AppRank) -> some View {
        let app = rank.app
        let isPinned = selection.isPinned(app)
        let quit = selection.quitRequest(of: app)
        return HStack(spacing: 6) {
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") { selection.togglePin(app) }
                .help(isPinned ? "Unpin \(app.name)" : "Pin \(app.name) to the sidebar")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: app.key)])
            } label: {
                // "in Finder" does not fit a 240 pt pane, even on its own line (measured).
                Label { ViewThatFits(in: .horizontal) { Text("Show\nin Finder"); EmptyView() } } icon: { Image(systemName: "folder") }
            }
            .accessibilityLabel("Show \(app.name) in Finder")
            // A bare executable name has no path to show.
            .disabled(!app.key.hasPrefix("/"))
            .help(app.key.hasPrefix("/") ? "Show \(app.name) in the Finder" : "\(app.name) has no app bundle to show")
            Button("Alert Rules…", systemImage: "bell") { _rulesShown.wrappedValue = true }
                .help("Mute alerts for \(app.name) or give it its own alert values")
            Button("Quit…", systemImage: "xmark.circle") { selection.signalRequest = quit }
                .disabled(quit == nil)
                .help(quitHelp(rank, quit))
        }
        .labelStyle(StackedLabelStyle())
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What Quit does, or why it cannot act.
    private func quitHelp(_ rank: AppRank, _ quit: SignalRequest?) -> String {
        if let process = selection.signallable { return "Ask \(process.name) to quit, or force quit it" }
        if let process = selection.process { return process.exited ? "Process has exited" : "Cannot quit this process" }
        if quit != nil { return "Quit \(rank.app.name), or force quit it" }
        if rank.processes.allSatisfy(\.exited) { return "No running processes" }
        // A bare executable name (zsh, node) can stand for other users' and unrelated processes.
        return "Select a process to quit"
    }

    /// "usual 21.0%, 4× usual" under a value; for an app usually idle, only how the value compares.
    private static func compare(_ value: Double, usual: Double, metric: Metric) -> String {
        let compared = UsualProfile.describe(value, usual: usual)
        return usual > 0 ? "usual \(metric.format(usual)), \(compared.prefix(1).lowercased() + compared.dropFirst())" : compared
    }

    /// A whole-minute, hour or day stride for about three x labels: more truncate at the inspector's 240 pt, and
    /// `.automatic(desiredCount:)` does not lower the count of a date axis (measured).
    static func xStride(seconds: Double) -> (Calendar.Component, Int) {
        let step = seconds / 3
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
    static func running(_ app: AppKey) -> [NSRunningApplication] {
        guard app.key.hasSuffix(".app") else { return [] }
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == app.key }
    }
}

/// The icon over the title, centred, filling the button: buttons in a row get one width and one height.
private struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.imageScale(.large)
            configuration.title.font(.caption).multilineTextAlignment(.center).lineLimit(2)
        }
        // The bezel's own side margins leave too little for a title at 240 pt; the title may use part of them.
        .padding(.horizontal, -5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An event's message with its date and time below; a click selects its time on the chart.
private struct EventRow: View {
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    let event: EventMark

    var body: some View {
        Button {
            history.selectTime(around: event.ts)
            selection.showChart = true
        } label: {
            VStack(alignment: .leading) {
                Text(event.message)
                Text(Date(timeIntervalSince1970: event.ts).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Select this time on the chart")
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
