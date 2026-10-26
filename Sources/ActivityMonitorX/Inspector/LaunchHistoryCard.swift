import AMXCore
import Charts
import SwiftUI

/// The app's process runs in the range (or span) as bars, one lane per process name for the 5 first names; a running
/// process's bar ends at the range's end. Show All lists every start and quit, newest first. A click on a bar or a row
/// selects its time on the chart.
struct LaunchHistoryCard: View {
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    let app: AppKey
    let processes: [ProcessRank]
    let color: Color
    /// The app whose list is shown; another app starts with the bars only.
    private let _showAllOf = State<String?>(initialValue: nil)
    /// The run under the pointer, and the pointer's place in the chart.
    private let _hover = State<(run: Run, point: CGPoint)?>(initialValue: nil)

    private struct Run: Equatable {
        let name: String
        let start: Double
        let end: Double
    }

    var body: some View {
        let from = history.span?.lowerBound ?? history.start, to = history.span?.upperBound ?? history.end
        let lanes = AppRank.byName(processes).prefix(5).map { $0[0].name }
        let runs = runs(lanes: Set(lanes), from: from, to: to)
        let launches = history.launches(of: app)
        let format = history.range.timeFormat
        CardSection("Launch History") {
            Chart {
                // Each lane's name above its bars, so the bars keep the pane's full width.
                ForEach(lanes, id: \.self) { name in
                    RuleMark(y: .value("Process", name))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, alignment: .leading, spacing: 4) {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .accessibilityHidden(true)
                }
                ForEach(runs.indices, id: \.self) { i in
                    BarMark(xStart: .value("Start", Self.date(runs[i].start)), xEnd: .value("End", Self.date(runs[i].end)),
                            y: .value("Process", runs[i].name), height: .fixed(8))
                        .foregroundStyle(color)
                        .accessibilityLabel(runs[i].name)
                        .accessibilityValue(span(runs[i], format))
                }
            }
            .chartXScale(domain: Self.date(from)...Self.date(to))
            .chartYScale(domain: lanes)
            .chartXAxis {
                let (unit, count) = InspectorView.xStride(seconds: to - from)
                AxisMarks(values: .stride(by: unit, count: count)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: AppTime.axisFormat(seconds: to - from))
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let location) = phase, let run = run(at: location, in: proxy, geo: geo, runs: runs) else {
                                _hover.wrappedValue = nil
                                return
                            }
                            // Set once per run: a rebuild per mouse move is not needed.
                            if _hover.wrappedValue?.run != run { _hover.wrappedValue = (run, location) }
                        }
                        .onTapGesture { location in
                            if let run = run(at: location, in: proxy, geo: geo, runs: runs) { select(run) }
                        }
                    // One accessibility button per bar: a click is not the only way to select a run.
                    if let plot = proxy.plotFrame.map({ geo[$0] }) {
                        ForEach(runs.indices, id: \.self) { i in
                            let run = runs[i]
                            if let x0 = proxy.position(forX: Self.date(run.start)), let x1 = proxy.position(forX: Self.date(run.end)),
                               let y = proxy.position(forY: run.name) {
                                Color.clear.frame(width: max(x1 - x0, 1), height: 8)
                                    .position(x: plot.minX + (x0 + x1) / 2, y: plot.minY + y)
                                    .accessibilityElement()
                                    .accessibilityLabel("Select \(run.name) run")
                                    .accessibilityValue(span(run, format))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { select(run) }
                            }
                        }
                    }
                }
            }
            .frame(height: CGFloat(lanes.count) * 36 + 24)
            .previewBeside(_hover.wrappedValue?.point) {
                if let run = _hover.wrappedValue?.run { card(run, format) }
            }
            .help("Each bar is one run of a process. Click a bar to select its time on the chart.")
            if launches.isEmpty {
                Text("No process started or quit in this range").foregroundStyle(.secondary)
            } else if _showAllOf.wrappedValue == app.key {
                ForEach(launches) { event in
                    Button {
                        history.selectTime(around: event.ts)
                        selection.showChart = true
                    } label: {
                        LabeledContent("\(event.isQuit ? "Quit" : "Started") \(event.name) (\(String(event.pid)))",
                                       value: Date(timeIntervalSince1970: event.ts).formatted(format))
                            .monospacedDigit()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Select this time on the chart")
                }
            } else {
                Button("Show All \(launches.count.formatted())") { _showAllOf.wrappedValue = app.key }
                    .help("Show all process starts and quits")
            }
        }
    }

    /// Each process of a lane from its start (or `from`) to its last record, or to `to` while it runs; at least one chart
    /// bucket wide, so a short run shows.
    private func runs(lanes: Set<String>, from: Double, to: Double) -> [Run] {
        processes.filter { lanes.contains($0.name) }.map { p in
            let start = max(p.startTime, from)
            let end = max(p.exited ? min(p.lastSeen, to) : to, start)
            return Run(name: p.name, start: start, end: min(to, max(end, start + history.loadedBucket)))
        }
    }

    /// The newest run under the point.
    private func run(at location: CGPoint, in proxy: ChartProxy, geo: GeometryProxy, runs: [Run]) -> Run? {
        guard let plot = proxy.plotFrame.map({ geo[$0] }),
              let date = proxy.value(atX: location.x - plot.minX, as: Date.self),
              let name = proxy.value(atY: location.y - plot.minY, as: String.self) else { return nil }
        let t = date.timeIntervalSince1970
        return runs.last { $0.name == name && $0.start <= t && t <= $0.end }
    }

    private func span(_ run: Run, _ format: Date.FormatStyle) -> String {
        "\(Self.date(run.start).formatted(format)) to \(Self.date(run.end).formatted(format)), \(Self.length(run))"
    }

    private static func length(_ run: Run) -> String {
        Duration.seconds(run.end - run.start).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    private func card(_ run: Run, _ format: Date.FormatStyle) -> some View {
        PreviewCard(size: .compact, title: run.name, top: Self.length(run),
                    sections: [.init(rows: [.init(label: "Start", value: Self.date(run.start).formatted(format)),
                                            .init(label: "End", value: Self.date(run.end).formatted(format))])])
    }

    private func select(_ run: Run) {
        history.span = run.start...run.end
        selection.showChart = true
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
}
