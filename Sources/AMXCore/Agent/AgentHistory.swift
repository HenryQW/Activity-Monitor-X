import Foundation

/// History tools: app ranking, one app's series, events and a window summary.
enum AgentHistory {
    static let tools = [topApps, appHistory, events, summarize]
    static let maxEvents = 500
    static let kinds = [EventKind.pressure, EventKind.thermal, EventKind.alert]

    private static let recordedFrom = """
        from in the output is where recording began when that is later than the requested start.
        """
    private static let buckets = """
        Bucket size follows the requested span (at most 120 buckets), so a long span on a short history gives few, wide buckets.
        """

    struct App: Encodable {
        let app: String, appKey: String, average: Double, peak: Double, processes: Int

        init(_ rank: AppRank) {
            (app, appKey, average, peak, processes) = (rank.app.name, rank.app.key, rank.average, rank.peak, rank.processes.count)
        }
    }

    /// The window's tracks, and the window start moved to where recording began, so averages cover recorded time only.
    static func load(_ w: QueryWindow, _ metric: Metric, _ context: AgentContext) throws
        -> (tracks: [ProcessTrack], from: Double) {
        let tracks = try context.reader.tracks(source: w.source, from: w.from, to: w.to, metric: metric)
        return (tracks, AppSeries.recordedStart(tracks, from: w.from))
    }

    private static func top(_ w: QueryWindow, _ metric: Metric, limit: Int, _ context: AgentContext) throws
        -> (from: Double, apps: [App]) {
        let (tracks, from) = try load(w, metric, context)
        return (from, AppSeries.ranking(tracks, from: from, to: w.to, bucket: w.bucket).prefix(limit).map(App.init))
    }

    static func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }

    // MARK: top_apps

    struct TopAppsArguments: Decodable { let from, to: AgentTools.Time?; let metric: String?; let limit: Int? }
    struct TopApps: Encodable { let from, to: Date; let metric, unit: String; let apps: [App] }

    static let topApps = AgentTools.Tool(
        "top_apps",
        """
        Apps ranked by their average over [from, to). \(recordedFrom) average is the time-weighted mean over \
        [from, to), time a process was not running counted as 0; peak is the highest bucket value; \
        processes counts distinct processes. \(buckets) \(AgentTools.units) \(AgentTools.times)
        """,
        schema: AgentTools.schema([AgentTools.timeProperties, AgentTools.metricProperty(),
                                   #""limit":{"type":"integer","minimum":1,"maximum":50,"default":10}"#])
    ) { (a: TopAppsArguments, context) -> TopApps in
        let metric = try AgentTools.metric(a.metric)
        let limit = a.limit ?? 10
        guard (1...50).contains(limit) else { throw AgentError.invalid("limit must be 1 to 50") }
        let w = try AgentTools.window(from: a.from, to: a.to, context: context)
        let (from, apps) = try top(w, metric, limit: limit, context)
        return TopApps(from: date(from), to: date(w.to), metric: metric.rawValue, unit: metric.unit, apps: apps)
    }

    // MARK: app_history

    struct AppHistoryArguments: Decodable { let app: String; let from, to: AgentTools.Time?; let metric: String? }
    struct Point: Encodable { let t: Date; let value: Double }
    struct AppHistory: Encodable {
        let app: String, appKeys: [String], metric: String, unit: String, bucketSeconds: Double, points: [Point]
    }

    static let appHistory = AgentTools.Tool(
        "app_history",
        """
        One app's series over the window, at most 120 points; each point is the mean over the bucket starting at t. \
        app is an exact app key (from top_apps) or an app name, case-insensitive; apps that share a name are summed. \
        "unknown app" means no data for that app in the window. Points start where recording began. \(buckets) \
        \(AgentTools.units) \(AgentTools.times)
        """,
        schema: AgentTools.schema([#""app":{"type":"string"}"#, AgentTools.timeProperties, AgentTools.metricProperty()],
                                  required: ["app"])
    ) { (a: AppHistoryArguments, context) -> AppHistory in
        let metric = try AgentTools.metric(a.metric)
        let w = try AgentTools.window(from: a.from, to: a.to, context: context)
        let (tracks, from) = try load(w, metric, context)
        let exact = tracks.filter { $0.app.key == a.app }
        let matched = exact.isEmpty ? tracks.filter { $0.app.name.caseInsensitiveCompare(a.app) == .orderedSame } : exact
        guard let first = matched.first else { throw AgentError.invalid("unknown app: \(a.app)") }
        return AppHistory(app: first.app.name, appKeys: Set(matched.map(\.app.key)).sorted(), metric: metric.rawValue,
                          unit: metric.unit, bucketSeconds: w.bucket, points: points(matched, from: from, w))
    }

    /// The tracks summed per bucket.
    static func points(_ tracks: [ProcessTrack], from: Double, _ w: QueryWindow) -> [Point] {
        var sums: [Double: Double] = [:]
        for p in AppSeries.stacked(tracks, from: from, to: w.to, bucket: w.bucket, top: .max) {
            sums[p.bucket, default: 0] += p.value
        }
        return sums.sorted { $0.key < $1.key }.map { Point(t: date($0.key), value: $0.value) }
    }

    // MARK: events

    struct EventsArguments: Decodable { let from, to: AgentTools.Time?; let kind: String? }
    struct Event: Encodable { let t: Date; let kind: String; let severity: Int; let message: String; let app: String?; let rule: String? }
    struct Events: Encodable { let events: [Event]; let truncated: Bool }

    static let events = AgentTools.Tool(
        "events",
        """
        Events in the window, oldest first, at most \(maxEvents); truncated is true when more matched. \
        kind is pressure (memory pressure; severity 0 normal, 1 warning, 2 critical) or thermal \
        (severity 0 nominal, 1 fair, 2 serious, 3 critical), or alert. An alert is any event with a rule; \
        pressure alerts are kind \(EventKind.pressure) with rule \(RuleName.pressure); kind \(EventKind.alert) holds \
        the process and app rules and the thermal, system CPU, swap and free space rules. Rules: \(RuleName.all.joined(separator: ", ")) \
        (alert severity 1 warning, 2 critical). app is the app of the process, if any. \(AgentTools.times)
        """,
        schema: AgentTools.schema([AgentTools.timeProperties,
                                   #""kind":{"type":"string","enum":["# + kinds.map { "\"\($0)\"" }.joined(separator: ",") + "]}"])
    ) { (a: EventsArguments, context) -> Events in
        if let kind = a.kind, !kinds.contains(kind) { throw AgentError.invalid("unknown kind: \(kind)") }
        let w = try AgentTools.window(from: a.from, to: a.to, context: context)
        let marks = try context.reader.events(from: w.from, to: w.to).filter { a.kind == nil || $0.kind == a.kind }
        return Events(events: marks.prefix(maxEvents).map {
            Event(t: date($0.ts), kind: $0.kind, severity: $0.severity, message: $0.message, app: $0.app?.name, rule: $0.rule)
        }, truncated: marks.count > maxEvents)
    }

    // MARK: summarize

    struct SummarizeArguments: Decodable { let from, to: AgentTools.Time? }
    struct System: Encodable { let cpuAvg, cpuMax, memUsedMax: Double; let pressureMax, thermalMax: String }
    struct Summary: Encodable {
        let from, to: Date
        /// Nil when the window holds no system samples.
        let system: System?
        let top: [String: [App]]
        let eventCounts: [String: Int]
    }

    static let summarize = AgentTools.Tool(
        "summarize",
        """
        A summary of the window. It gives system CPU (% of all cores) average and maximum, used memory maximum (bytes), \
        the worst memory pressure (normal, warning, critical) and thermal state (nominal, fair, serious, critical); \
        the top 3 apps for each of \(Metric.recorded.map(\.rawValue).joined(separator: ", ")) (as in top_apps); \
        and event counts by kind. \(recordedFrom) cpu_avg is the mean of bucket means; maximums are of bucket means; \
        event counts start at the reported from. system is absent without samples. \(buckets) \
        \(AgentTools.units) \(AgentTools.times)
        """,
        schema: AgentTools.schema([AgentTools.timeProperties])
    ) { (a: SummarizeArguments, context) -> Summary in
        let w = try AgentTools.window(from: a.from, to: a.to, context: context)
        var top: [String: [App]] = [:]
        var from = w.from
        for metric in Metric.recorded {
            // Every metric reads the same rows, so the recorded start is the same.
            (from, top[metric.rawValue]) = try Self.top(w, metric, limit: 3, context)
        }
        let points = try context.reader.system(source: w.source, from: from, to: w.to, bucket: w.bucket)
        let system = points.isEmpty ? nil : System(
            cpuAvg: points.reduce(0) { $0 + $1.cpu } / Double(points.count),
            cpuMax: points.map(\.cpu).max()!,
            memUsedMax: points.map(\.memUsed).max()!,
            pressureMax: SystemState.pressure(points.map(\.pressureLevel).max()!),
            thermalMax: SystemState.thermal(points.map(\.thermalState).max()!))
        let counts = Dictionary(grouping: try context.reader.events(from: from, to: w.to), by: \.kind).mapValues(\.count)
        return Summary(from: date(from), to: date(w.to), system: system, top: top, eventCounts: counts)
    }
}
