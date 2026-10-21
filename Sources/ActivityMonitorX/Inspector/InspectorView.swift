import AMXCore
import Charts
import SwiftUI

/// The selected app for the range (or span): its series, peak process, events and processes, with Quit / Force Quit.
struct InspectorView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection

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
        } else {
            ContentUnavailableView("No App Selected", systemImage: "sidebar.trailing",
                                   description: Text("Select an app to see its details."))
        }
    }

    private func details(_ rank: AppRank, series: [SeriesPoint], events: [EventMark]) -> some View {
        let metric = history.metric
        // A pinned Timeline colours its app from the app's own series; every other view uses the top-5 mapping.
        let pinned: Bool = if case .pinned(let focus) = selection.sidebar { focus.key == rank.app.key } else { false }
        let color = AppPalette.colors(for: pinned ? series : history.range == .live ? live.stacked : history.stacked)[rank.app] ?? .secondary
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
                Text(rank.processes.count == 1 ? "1 process" : "\(rank.processes.count) processes")
                    .foregroundStyle(.secondary)
                Chart(series.indices, id: \.self) { i in
                    AreaMark(x: .value("Time", Date(timeIntervalSince1970: series[i].bucket)),
                             y: .value(metric.label, series[i].value))
                        .foregroundStyle(color.opacity(0.6))
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
            if let peak = rank.processes.max(by: { $0.peak < $1.peak }) {
                Section("Peak Process") {
                    LabeledContent("\(peak.name) (\(String(peak.pid)))", value: metric.format(peak.peak))
                }
            }
            Section("Events") {
                if events.isEmpty {
                    Text("No events").foregroundStyle(.secondary)
                }
                ForEach(events.indices, id: \.self) { i in
                    VStack(alignment: .leading) {
                        Text(events[i].message)
                        Text(Date(timeIntervalSince1970: events[i].ts).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Processes") {
                ForEach(rank.processes, id: \.key) { p in
                    LabeledContent {
                        HStack {
                            if p.exited { Text("Exited") }
                            Text(metric.format(p.average)).monospacedDigit()
                        }
                    } label: {
                        Text(p.name)
                        Text("PID \(String(p.pid))")
                    }
                    .foregroundStyle(p.exited ? .secondary : .primary)
                    .tag(ProcKey(p))
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            HStack {
                Button("Quit") { request(SIGTERM) }
                Button("Force Quit") { request(SIGKILL) }
            }
            .disabled(selection.signallable == nil)
            .padding(10)
        }
    }

    private func request(_ signal: Int32) {
        selection.signalRequest = selection.signallable.map { SignalRequest(process: $0, signal: signal) }
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
