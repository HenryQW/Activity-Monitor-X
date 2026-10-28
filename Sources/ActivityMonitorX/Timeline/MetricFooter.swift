import AMXCore
import Charts
import SwiftUI

/// The Apps screen's footer for the chosen metric, in the shared `ScreenFooter`: the system's trend as a small line
/// and the figures the table does not give, each value over its label (no box, no title: the toolbar names the metric). Range figures come from the system samples (the span's, when one is selected); Live reads the last
/// 5 min of them. Figures marked "now" the app reads itself every 2 s (`HostReader`, `PowerReader`); none is stored.
struct MetricFooter: View {
    let metric: Metric
    let live: Bool
    /// The chart's stacked series: Energy has no system series, so its graph is the apps' total.
    let stacked: [SeriesPoint]
    @Environment(HistoryModel.self) private var history
    private let _now = State(initialValue: Now())
    private let _livePoints = State<[SystemPoint]>(initialValue: [])

    struct Now {
        var cpu: HostReader.CPUSplit?
        var load: [Double]?
        var memory: HostReader.Memory?
        var power: PowerReading?
    }

    /// The numbers roll for a change the user made (metric, range, span), once its data has loaded; a Live tick, a reload
    /// of the same range and the app's own 2 s readings swap them.
    private struct Roll: Equatable {
        let metric: Metric
        let range: HistoryRange
        let span: ClosedRange<Double>?
        let state: LoadState
    }

    private struct GraphPoint: Identifiable {
        var id: String { "\(series) \(bucket)" }
        let bucket: Double
        let series: String
        let value: Double
    }

    var body: some View {
        let points = live ? _livePoints.wrappedValue : history.system.filter { p in history.span.map { $0.contains(p.bucket) } ?? true }
        ScreenFooter(figures: stats(points), roll: Roll(metric: metric, range: history.range, span: history.span, state: history.state)) {
            graph(points)
        }
        .accessibilityLabel("\(metric.label) summary")
        .task(id: "\(live) \(metric.label)") { await read() }
    }

    // MARK: - Graph

    /// The trend with no axes or title; two series (read and write, in and out) are the accent and grey, as the help says.
    private func graph(_ points: [SystemPoint]) -> some View {
        let (title, series, percent) = graphSeries(points)
        let names = series.reduce(into: [String]()) { if !$0.contains($1.series) { $0.append($1.series) } }
        return Group {
            if series.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                chart(series, title: title, names: names, percent: percent)
            }
        }
        .frame(width: 140, height: 32)
        .accessibilityLabel("\(title) graph")
        .help((live ? "\(title) in the last 5 minutes" : "\(title) in the \(history.span == nil ? "range" : "selected span")")
              + (names.count > 1 ? ": \(names[0]) in the accent colour, \(names[1]) in grey" : ""))
    }

    private func chart(_ series: [GraphPoint], title: String, names: [String], percent: Bool) -> some View {
        Chart(series) { p in
            if names.count == 1 {
                AreaMark(x: .value("Time", Date(timeIntervalSince1970: p.bucket)), y: .value(title, p.value))
                    .foregroundStyle(Color.accentColor.opacity(0.25))
            }
            LineMark(x: .value("Time", Date(timeIntervalSince1970: p.bucket)), y: .value(title, p.value),
                     series: .value("Series", p.series))
                .foregroundStyle(by: .value("Series", p.series))
        }
        .chartForegroundStyleScale(domain: names, range: [Color.accentColor, Color.secondary].prefix(names.count).map { $0 })
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(percent ? 100 : max(series.map(\.value).max() ?? 0, 1)))
    }

    /// The graph's title, its series and whether it is a percentage.
    private func graphSeries(_ points: [SystemPoint]) -> (String, [GraphPoint], Bool) {
        func one(_ name: String, _ value: KeyPath<SystemPoint, Double>) -> [GraphPoint] {
            points.map { GraphPoint(bucket: $0.bucket, series: name, value: $0[keyPath: value]) }
        }
        switch metric {
        case .cpu: return ("CPU", one("CPU", \.cpu), true)
        case .memory: return ("Memory Pressure", one("Memory Pressure", \.pressurePct), true)
        case .disk: return ("Disk", one("Read", \.diskR) + one("Write", \.diskW), false)
        case .network: return ("Network", one("In", \.netIn) + one("Out", \.netOut), false)
        case .gpu: return ("GPU", one("GPU", \.gpu), true)
        default:  // Energy; Score has no footer
            let totals = energyTotals
            return ("Energy Impact", totals.map { GraphPoint(bucket: $0.bucket, series: "Energy Impact", value: $0.value) }, false)
        }
    }

    /// The apps' total energy impact per chart bucket, in time order.
    private var energyTotals: [(bucket: Double, value: Double)] {
        Dictionary(grouping: stacked, by: \.bucket).map { ($0.key, $0.value.reduce(0) { $0 + $1.value }) }.sorted { $0.0 < $1.0 }
    }

    // MARK: - Figures

    private func stats(_ points: [SystemPoint]) -> [FooterFigure] {
        let now = _now.wrappedValue
        let window = live ? "in the last 5 minutes" : history.span == nil ? "in the range" : "in the selected span"
        let bucket = live ? 5 : history.loadedBucket
        /// The latest value in Live, else the average.
        func level(_ value: KeyPath<SystemPoint, Double>) -> Double? {
            live ? points.last?[keyPath: value] : points.isEmpty ? nil : points.reduce(0) { $0 + $1[keyPath: value] } / Double(points.count)
        }
        func peak(_ value: KeyPath<SystemPoint, Double>) -> Double? { points.map { $0[keyPath: value] }.max() }
        func total(_ value: KeyPath<SystemPoint, Double>) -> Double? {
            points.isEmpty ? nil : points.reduce(0) { $0 + $1[keyPath: value] } * bucket
        }
        func temperature(_ value: KeyPath<SystemPoint, Double?>) -> String {
            let values = points.compactMap { $0[keyPath: value] }
            guard let t = live ? values.last : values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) else { return "No data" }
            return "\(t.formatted(.number.precision(.fractionLength(0)))) °C"
        }
        func text(_ value: Double?, _ format: (Double) -> String = metric.format) -> String { value.map(format) ?? "No data" }
        /// A figure the app reads now: "now" in its label outside Live.
        func current(_ label: String, _ value: String, _ help: String) -> FooterFigure {
            FooterFigure(label: live ? label : "\(label) now", value: value, help: "\(help) now, read by this app; not recorded")
        }
        func percent(_ value: Double?) -> String { text(value, Metric.cpu.format) }
        /// A total from bucket means times the full bucket width: a partly recorded bucket counts too much.
        func about(_ value: Double?) -> String { value.map { "About " + Metric.bytes($0) } ?? "No data" }
        let levelLabel = live ? "Now" : "Average"
        let levelHelp = live ? "The latest recorded value" : "The average \(window)"
        let bytes = Metric.memory.format

        switch metric {
        case .cpu:
            return [
                FooterFigure(label: levelLabel, value: percent(level(\.cpu)), help: levelHelp),
                FooterFigure(label: "CPU temperature", value: temperature(\.tempCPU), help: "The CPU temperature, \(live ? "latest" : "average") \(window)"),
                current("User", percent(now.cpu?.user), "The share of CPU time in apps"),
                current("System", percent(now.cpu?.system), "The share of CPU time in the system"),
                current("Load average", now.load.map { $0.map { $0.formatted(.number.precision(.fractionLength(1))) }.joined(separator: ", ") } ?? "No data",
                        "The 1, 5 and 15 minute load averages"),
            ]
        case .memory:
            let pressure = live ? points.last?.pressureLevel : points.map(\.pressureLevel).filter { $0 > 0 }.max()
            return [
                FooterFigure(label: "Physical Memory", value: bytes(Double(ProcessInfo.processInfo.physicalMemory)), help: "The memory installed in this Mac"),
                FooterFigure(label: "Memory Used", value: text(level(\.memUsed), bytes), help: "App, wired and compressed memory: \(levelHelp.lowercased())"),
                current("Cached Files", text(now.memory.map { Double($0.cached) }, bytes), "Memory that holds recently used files"),
                FooterFigure(label: "Swap Used", value: text(live ? points.last?.swapUsed : peak(\.swapUsed), bytes),
                     help: live ? "The latest recorded swap used" : "The most swap used \(window)"),
                current("App Memory", text(now.memory.map { Double($0.app) }, bytes), "Memory that apps use"),
                current("Wired Memory", text(now.memory.map { Double($0.wired) }, bytes), "Memory that the system keeps in RAM"),
                FooterFigure(label: "Compressed", value: text(level(\.memCompressed), bytes), help: "Compressed memory: \(levelHelp.lowercased())"),
                FooterFigure(label: "Pressure", value: pressure.map { SystemState.pressure($0).capitalized } ?? "No data",
                     help: live ? "The latest recorded memory pressure" : "The highest memory pressure \(window)",
                     severity: pressure.map(SystemState.pressureSeverity) ?? 0),
            ]
        case .disk:
            return [
                FooterFigure(label: "Read", value: text(level(\.diskR)), help: "Bytes read per second: \(levelHelp.lowercased())"),
                FooterFigure(label: "Write", value: text(level(\.diskW)), help: "Bytes written per second: \(levelHelp.lowercased())"),
                FooterFigure(label: "Total read", value: about(total(\.diskR)), help: "An estimate of the bytes read \(window)"),
                FooterFigure(label: "Total written", value: about(total(\.diskW)), help: "An estimate of the bytes written \(window)"),
                FooterFigure(label: "Operations", value: text(level(\.diskIOPS)) { "\($0.formatted(.number.precision(.fractionLength(0))))/s" },
                     help: "Read and write operations per second: \(levelHelp.lowercased())"),
                FooterFigure(label: "Latency", value: text(level(\.diskLatMs)) { "\($0.formatted(.number.precision(.fractionLength(2)))) ms" },
                     help: "The time per operation: \(levelHelp.lowercased())"),
            ]
        case .network:
            return [
                FooterFigure(label: "In", value: text(level(\.netIn)), help: "Bytes received per second: \(levelHelp.lowercased())"),
                FooterFigure(label: "Out", value: text(level(\.netOut)), help: "Bytes sent per second: \(levelHelp.lowercased())"),
                FooterFigure(label: "Total received", value: about(total(\.netIn)), help: "An estimate of the bytes received \(window)"),
                FooterFigure(label: "Total sent", value: about(total(\.netOut)), help: "An estimate of the bytes sent \(window)"),
            ]
        case .gpu:
            let thermal = live ? points.last?.thermalState : points.map(\.thermalState).max()
            return [
                FooterFigure(label: levelLabel, value: percent(level(\.gpu)), help: levelHelp),
                FooterFigure(label: "GPU temperature", value: temperature(\.tempGPU), help: "The GPU temperature, \(live ? "latest" : "average") \(window)"),
                FooterFigure(label: "Thermal state", value: thermal.map { SystemState.thermal($0).capitalized } ?? "No data",
                     help: live ? "The latest recorded thermal state" : "The highest thermal state \(window)",
                     severity: thermal.map(SystemState.thermalSeverity) ?? 0),
            ]
        default:  // Energy; Score has no footer
            let totals = energyTotals.map(\.value)
            let average = live ? totals.last : totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
            var rows = [
                FooterFigure(label: levelLabel, value: text(average), help: "All apps' energy impact: \(levelHelp.lowercased())"),
            ]
            guard let power = now.power else { return rows }
            let source = power.adapterConnected ? "Power adapter" + (power.adapterRating.map { ", \(Int($0)) W" } ?? "") : "Battery"
            rows.append(current("Power source", source, "What powers this Mac"))
            rows.append(current("System power", power.systemWatts.map { "\($0.formatted(.number.precision(.fractionLength(1)))) W" } ?? "Not reported",
                                "The watts this Mac uses"))
            if let battery = power.battery {
                rows.append(current("Battery", (battery.percent.map { "\($0)%" } ?? "No data") + (battery.charging ? ", charging" : ""),
                                    "The battery charge"))
                func minutes(_ m: Int?) -> String {
                    m.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "Calculating"
                }
                if !power.adapterConnected {
                    rows.append(current("Time to empty", minutes(battery.minutesToEmpty), "The Mac's estimate of the time on battery"))
                } else {
                    rows.append(current("Time to full", battery.charging ? minutes(battery.minutesToFull) : battery.percent == 100 ? "Full" : "Not charging",
                                        "The Mac's estimate of the time to a full charge"))
                }
            }
            return rows
        }
    }

    // MARK: - Reading

    /// Every 2 s while the window shows: the figures read now, and in Live the last 5 min of system samples.
    private func read() async {
        var before = HostReader.cpuTicks()
        while !Task.isCancelled {
            if MainWindowRef.windowShown {
                if live, let pool = try? history.openPool() {
                    // On the 5 s bucket grid, so a read with no new rows returns the same buckets and draws nothing; rounded up,
                    // so the newest row is in.
                    let end = (Date().timeIntervalSince1970 / 5).rounded(.up) * 5
                    let points = await Task.detached { try? HistoryReader(pool: pool).system(source: .raw, from: end - 300, to: end, bucket: 5) }.value
                    if let points, points.count != _livePoints.wrappedValue.count || points.last?.bucket != _livePoints.wrappedValue.last?.bucket {
                        _livePoints.wrappedValue = points
                    }
                }
                // Only what the metric shows.
                switch metric {
                case .cpu:
                    let ticks = HostReader.cpuTicks()
                    let split = ticks.flatMap { t in before.flatMap { HostReader.CPUSplit(t, since: $0) } }
                    (_now.wrappedValue.cpu, _now.wrappedValue.load) = (split ?? _now.wrappedValue.cpu, HostReader.loadAverage())
                    before = ticks
                case .memory: _now.wrappedValue.memory = HostReader.memory()
                case .energy: _now.wrappedValue.power = PowerReader.read()
                default: break
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
