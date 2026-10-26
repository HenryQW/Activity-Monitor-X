import AMXCore
import Charts
import SwiftUI

/// The Apps screen's footer for the chosen metric: a graph of the system's value and
/// its figures. Range figures come from the system samples (the span's, when one is selected); Live reads the last
/// 5 min of them. Figures marked "now" the app reads itself every 2 s (`HostReader`, `PowerReader`); none is stored.
struct MetricFooter: View {
    let metric: Metric
    let live: Bool
    /// The range's (or span's) ranking: its first app is the busiest.
    let ranking: [AppRank]
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

    private struct Stat: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let help: String
        /// 1 warning, 2 critical: the value shows `SeverityIcon`.
        var severity = 0
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
        let stats = stats(points)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                graph(points).frame(width: 220)
                statsBox(stats)
            }
            // Narrow content: the figures alone.
            statsBox(stats)
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout)
        .padding(Layout.padding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metric.label) summary")
        .task(id: "\(live) \(metric.label)") { await read() }
    }

    // MARK: - Graph

    private func graph(_ points: [SystemPoint]) -> some View {
        let (title, series, percent) = graphSeries(points)
        let names = series.reduce(into: [String]()) { if !$0.contains($1.series) { $0.append($1.series) } }
        return GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if series.isEmpty {
                    Text("No data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
                    .chartLegend(names.count > 1 ? .visible : .hidden)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...(percent ? 100 : max(series.map(\.value).max() ?? 0, 1)))
                    .frame(height: 56)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) graph")
        .help(live ? "\(title) in the last 5 minutes" : "\(title) in the \(history.span == nil ? "range" : "selected span")")
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

    private func statsBox(_ stats: [Stat]) -> some View {
        let half = (stats.count + 1) / 2
        return GroupBox {
            HStack(alignment: .top, spacing: 16) {
                column(stats[..<half])
                column(stats[half...])
            }
        }
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .leading)
    }

    private func column(_ stats: ArraySlice<Stat>) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                if i > 0 { Divider() }
                HStack(spacing: 4) {
                    Text(stat.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if stat.severity > 0 { SeverityIcon(severity: stat.severity) }
                    Text(stat.value)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.smooth(0.25), value: Roll(metric: metric, range: history.range, span: history.span, state: history.state))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .help(stat.help)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func stats(_ points: [SystemPoint]) -> [Stat] {
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
        func current(_ label: String, _ value: String, _ help: String) -> Stat {
            Stat(label: live ? label : "\(label) now", value: value, help: "\(help) now, read by this app; not recorded")
        }
        func percent(_ value: Double?) -> String { text(value, Metric.cpu.format) }
        /// A total from bucket means times the full bucket width: a partly recorded bucket counts too much.
        func about(_ value: Double?) -> String { value.map { "About " + Metric.bytes($0) } ?? "No data" }
        let levelLabel = live ? "Now" : "Average"
        let levelHelp = live ? "The latest recorded value" : "The average \(window)"
        let peakHelp = "The highest chart value \(window)"
        let busiest = Stat(label: "Busiest app", value: ranking.first.map { "\($0.app.name) \(metric.format($0.average))" } ?? "None",
                           help: "The app with the highest average \(window)")
        let bytes = Metric.memory.format

        switch metric {
        case .cpu:
            return [
                Stat(label: levelLabel, value: percent(level(\.cpu)), help: levelHelp),
                Stat(label: "Peak", value: percent(peak(\.cpu)), help: peakHelp),
                busiest,
                Stat(label: "CPU temperature", value: temperature(\.tempCPU), help: "The CPU temperature, \(live ? "latest" : "average") \(window)"),
                current("User", percent(now.cpu?.user), "The share of CPU time in apps"),
                current("System", percent(now.cpu?.system), "The share of CPU time in the system"),
                current("Idle", percent(now.cpu?.idle), "The share of CPU time idle"),
                current("Load average", now.load.map { $0.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ") } ?? "No data",
                        "The 1, 5 and 15 minute load averages"),
            ]
        case .memory:
            let pressure = live ? points.last?.pressureLevel : points.map(\.pressureLevel).filter { $0 > 0 }.max()
            return [
                Stat(label: "Physical Memory", value: bytes(Double(ProcessInfo.processInfo.physicalMemory)), help: "The memory installed in this Mac"),
                Stat(label: "Memory Used", value: text(level(\.memUsed), bytes), help: "App, wired and compressed memory: \(levelHelp.lowercased())"),
                current("Cached Files", text(now.memory.map { Double($0.cached) }, bytes), "Memory that holds recently used files"),
                Stat(label: "Swap Used", value: text(live ? points.last?.swapUsed : peak(\.swapUsed), bytes),
                     help: live ? "The latest recorded swap used" : "The most swap used \(window)"),
                current("App Memory", text(now.memory.map { Double($0.app) }, bytes), "Memory that apps use"),
                current("Wired Memory", text(now.memory.map { Double($0.wired) }, bytes), "Memory that the system keeps in RAM"),
                Stat(label: "Compressed", value: text(level(\.memCompressed), bytes), help: "Compressed memory: \(levelHelp.lowercased())"),
                Stat(label: "Pressure", value: pressure.map { SystemState.pressure($0).capitalized } ?? "No data",
                     help: live ? "The latest recorded memory pressure" : "The highest memory pressure \(window)",
                     severity: pressure.map { $0 >= 4 ? 2 : $0 >= 2 ? 1 : 0 } ?? 0),
            ]
        case .disk:
            return [
                Stat(label: "Read", value: text(level(\.diskR)), help: "Bytes read per second: \(levelHelp.lowercased())"),
                Stat(label: "Write", value: text(level(\.diskW)), help: "Bytes written per second: \(levelHelp.lowercased())"),
                Stat(label: "Total read", value: about(total(\.diskR)), help: "An estimate of the bytes read \(window)"),
                Stat(label: "Total written", value: about(total(\.diskW)), help: "An estimate of the bytes written \(window)"),
                Stat(label: "Operations", value: text(level(\.diskIOPS)) { "\($0.formatted(.number.precision(.fractionLength(0))))/s" },
                     help: "Read and write operations per second: \(levelHelp.lowercased())"),
                Stat(label: "Latency", value: text(level(\.diskLatMs)) { "\($0.formatted(.number.precision(.fractionLength(2)))) ms" },
                     help: "The time per operation: \(levelHelp.lowercased())"),
                busiest,
            ]
        case .network:
            return [
                Stat(label: "In", value: text(level(\.netIn)), help: "Bytes received per second: \(levelHelp.lowercased())"),
                Stat(label: "Out", value: text(level(\.netOut)), help: "Bytes sent per second: \(levelHelp.lowercased())"),
                Stat(label: "Total received", value: about(total(\.netIn)), help: "An estimate of the bytes received \(window)"),
                Stat(label: "Total sent", value: about(total(\.netOut)), help: "An estimate of the bytes sent \(window)"),
                Stat(label: "Peak in", value: text(peak(\.netIn)), help: peakHelp),
                Stat(label: "Peak out", value: text(peak(\.netOut)), help: peakHelp),
                busiest,
            ]
        case .gpu:
            let thermal = live ? points.last?.thermalState : points.map(\.thermalState).max()
            return [
                Stat(label: levelLabel, value: percent(level(\.gpu)), help: levelHelp),
                Stat(label: "Peak", value: percent(peak(\.gpu)), help: peakHelp),
                busiest,
                Stat(label: "GPU temperature", value: temperature(\.tempGPU), help: "The GPU temperature, \(live ? "latest" : "average") \(window)"),
                Stat(label: "Thermal state", value: thermal.map { SystemState.thermal($0).capitalized } ?? "No data",
                     help: live ? "The latest recorded thermal state" : "The highest thermal state \(window)",
                     severity: thermal.map { $0 >= 3 ? 2 : $0 >= 2 ? 1 : 0 } ?? 0),
            ]
        default:  // Energy; Score has no footer
            let totals = energyTotals.map(\.value)
            let average = live ? totals.last : totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
            var rows = [
                Stat(label: levelLabel, value: text(average), help: "All apps' energy impact: \(levelHelp.lowercased())"),
                Stat(label: "Peak", value: text(totals.max()), help: peakHelp),
                busiest,
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
                    let end = Date().timeIntervalSince1970
                    let points = await Task.detached { try? HistoryReader(pool: pool).system(source: .raw, from: end - 300, to: end, bucket: 5) }.value
                    if let points { _livePoints.wrappedValue = points }
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
