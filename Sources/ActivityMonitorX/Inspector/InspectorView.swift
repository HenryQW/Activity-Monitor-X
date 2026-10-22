import AMXCore
import AppKit
import Charts
import SwiftUI

/// The selected app for the range (or span): its series, peak process, events and processes, with Quit / Force Quit;
/// with no app selected, a summary of the range.
struct InspectorView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    /// The app whose full process list is shown; another app starts short again.
    private let _showAllOf = State<String?>(initialValue: nil)

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

    /// With no app selected, the range (or span) at a glance: the total, the top apps and the warnings, so
    /// "what slows my Mac" needs no click. A click on an app, or on an event that names one, selects it.
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
        return List(selection: Binding<AppKey?>(get: { nil }, set: { selection.app = $0 })) {
            Section {
                Text(history.scope?.name ?? "All Apps").font(.title3.bold())
                LabeledContent("Average", value: metric.format(ranking.reduce(0) { $0 + $1.average }))
                    .help("The sum of the listed apps' averages: hidden quiet system processes are not counted.")
                LabeledContent("Peak", value: metric.format(AppSeries.peakTotal(points, bucket: history.range.chartBucket, in: span)))
                    .help("The highest bucket total in the chart, every process counted.")
            }
            .monospacedDigit()
            Section("Top Apps") {
                if top.isEmpty {
                    Text(selection.search.isEmpty ? "No apps" : "No app matches the search").foregroundStyle(.secondary)
                }
                ForEach(top) { rank in
                    LabeledContent {
                        Text(metric.format(rank.average)).monospacedDigit()
                    } label: {
                        AppLabel(app: rank.app, color: colors[rank.app], pinned: selection.isPinned(rank.app),
                                 detail: details[rank.app.key])
                    }
                    .tag(rank.app)
                }
            }
            // Live loads no events.
            if !isLive {
                Section(events.isEmpty ? "Warnings" : "Warnings (\(events.count.formatted()))") {
                    if events.isEmpty {
                        Text("No warnings").foregroundStyle(.secondary)
                    }
                    // The latest five; the chart's markers hold the rest.
                    ForEach(Array(events.suffix(5).reversed().enumerated()), id: \.offset) { _, event in
                        EventRow(event: event).tag(event.app)
                    }
                }
            }
        }
    }

    private func details(_ rank: AppRank, series: [SeriesPoint], events: [EventMark]) -> some View {
        let metric = history.metric
        // A pinned Timeline colours its app from the app's own series; every other view uses the top-5 mapping.
        let pinned: Bool = if case .pinned(let focus) = selection.sidebar { focus.key == rank.app.key } else { false }
        let color = AppPalette.colors(for: pinned ? series : history.range == .live ? live.stacked : history.stacked)[rank.app] ?? .secondary
        let detail = AppKey.details(for: (history.range == .live ? live.ranking : history.ranking).map(\.app) + [rank.app])[rank.app.key]
        let running = rank.processes.filter { !$0.exited }
        let exited = rank.processes.filter(\.exited)
        // A long-gone helper never hides a running process: only the exited rows are cut, to the top 20 by average.
        let exitedRows = AppRank.byName(exited)
        let shownExited = exitedRows.prefix(_showAllOf.wrappedValue == rank.app.key ? .max : 20)
        let selected = Binding<ProcKey?>(
            get: { selection.process.map(ProcKey.init) },
            set: { key in selection.process = rank.processes.first { ProcKey($0) == key } })
        return List(selection: selected) {
            Section {
                Label {
                    Text(rank.app.name).font(.title3.bold()).help(rank.app.key)
                } icon: {
                    Circle().fill(color).frame(width: 10, height: 10)
                }
                // Another app in the range has this name ("Claude" and "claude").
                if let detail { Text(detail).foregroundStyle(.secondary) }
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
            if let entry = history.glossaryEntry(app: rank.app, process: selection.process) {
                Section("About") {
                    Text(entry.title).font(.headline)
                    if let vendor = entry.vendor { Text(vendor).foregroundStyle(.secondary) }
                    Text(entry.description)
                    if entry.expectedHigh == true {
                        Text("High use is normal for this process.").foregroundStyle(.secondary)
                    }
                }
            }
            if let peak = rank.processes.max(by: { $0.peak < $1.peak }) {
                Section("Peak Process") {
                    LabeledContent("\(peak.name) (\(String(peak.pid)))", value: metric.format(peak.peak))
                }
            }
            Section("Events") {
                if events.isEmpty {
                    Text("No events").foregroundStyle(.secondary)
                }
                ForEach(events.indices, id: \.self) { EventRow(event: events[$0]) }
            }
            if !running.isEmpty {
                Section("Running (\(running.count.formatted()))") {
                    // By name: the first process of a name changes as averages shift (each second in Live), which would close an open row.
                    ForEach(AppRank.byName(running), id: \.[0].name) { processRows($0, of: rank.app) }
                }
            }
            if !exited.isEmpty {
                Section("Exited (\(exited.count.formatted()))") {
                    ForEach(shownExited, id: \.[0].name) { processRows($0, of: rank.app) }
                    if shownExited.count < exitedRows.count {
                        Button("Show All \(exited.count.formatted())") { _showAllOf.wrappedValue = rank.app.key }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        // A solid bar, apart from the list, keeps the destructive buttons away from the app's name.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let apps = selection.process == nil ? Self.running(rank.app) : []
            VStack(spacing: 0) {
                Divider()
                HStack {
                    if let process = selection.signallable {
                        Button("Quit") { selection.signalRequest = SignalRequest(process: process, signal: SIGTERM) }
                        Button("Force Quit") { selection.signalRequest = SignalRequest(process: process, signal: SIGKILL) }
                    } else if let process = selection.process {
                        Text(process.exited ? "Process has exited" : "Cannot quit this process").foregroundStyle(.secondary)
                    } else if !apps.isEmpty {
                        Button("Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGTERM) }
                        Button("Force Quit") { selection.signalRequest = SignalRequest(app: rank.app.name, running: apps, signal: SIGKILL) }
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
