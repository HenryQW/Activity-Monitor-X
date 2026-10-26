import AMXCore
import Foundation
import GRDB
import Observation
import os

enum LoadState: Equatable {
    case loading, empty, ready
    case failed(String)
}

@Observable @MainActor
final class HistoryModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "history")
    /// The quick range ending now; with `custom`, the smallest range that covers it, for its source and chart bucket.
    var range: HistoryRange {
        get { shown }
        set { show(newValue, custom: nil) }
    }
    private var shown: HistoryRange = .day
    /// The window chosen in Custom Range; nil is `range` ending now. Set through `show(from:to:)`; a new range clears it.
    private(set) var custom: ClosedRange<Double>?
    func show(from: Double, to: Double) {
        show(.covering(from: from, to: to, now: Date().timeIntervalSince1970), custom: from...to)
    }
    /// What Live was entered from, for `toggleLive()`; 24H until Live has been entered.
    private(set) var beforeLive: (range: HistoryRange, custom: ClosedRange<Double>?) = (.day, nil)
    /// Live on, or back to the range (and custom window) it was entered from.
    func toggleLive() {
        guard shown == .live else { return range = .live }
        let back = beforeLive
        if let window = back.custom { show(from: window.lowerBound, to: window.upperBound) } else { range = back.range }
    }
    /// The time shown: the custom window, else the range ending now.
    var window: ClosedRange<Double> {
        custom ?? { let now = Date().timeIntervalSince1970; return (now - range.seconds)...now }()
    }
    /// The range a zoom out opens and the one a zoom in opens with no span; nil in Live and at the ends.
    var widerRange: HistoryRange? { range == .live ? nil : .wider(than: window.upperBound - window.lowerBound) }
    var narrowerRange: HistoryRange? { range == .live ? nil : .narrower(than: window.upperBound - window.lowerBound) }
    /// Zoom out: a range ends now, so it widens to the next range; a custom window widens around its middle, and the
    /// range itself when that ends now.
    func zoomOut() {
        guard let wider = widerRange else { return }
        let now = Date().timeIntervalSince1970
        let to = wider.window(around: window, now: now)
        if zoomsOutToRange(now: now) { return range = wider }
        show(from: to.lowerBound, to: to.upperBound)
    }
    /// Zoom out ends now: it opens the quick range, which follows the clock.
    func zoomsOutToRange(now: Double = Date().timeIntervalSince1970) -> Bool {
        guard let wider = widerRange else { return false }
        return custom == nil || wider.window(around: window, now: now).upperBound >= now
    }
    /// Zoom in: the span when one is selected, else the next narrower range around the middle of the window shown.
    func zoomIn() {
        if let span { return show(from: span.lowerBound, to: span.upperBound) }
        guard let narrower = narrowerRange else { return }
        let to = narrower.window(around: window, now: Date().timeIntervalSince1970)
        show(from: to.lowerBound, to: to.upperBound)
    }
    /// Zoom in has a target: a span, or a narrower range.
    var canZoomIn: Bool { range != .live && (span != nil || narrowerRange != nil) }
    private func show(_ range: HistoryRange, custom: ClosedRange<Double>?) {
        guard range != shown || custom != self.custom else { return }
        if range == .live && shown != .live { beforeLive = (shown, self.custom) }
        // The data on screen stays while the next loads where it still fits: into Live (Apps shows it until Live has its own
        // data), and back to the range Live was entered from (it is still that range's data).
        let back = shown == .live && range == beforeLive.range && custom == beforeLive.custom
        (shown, self.custom) = (range, custom)
        span = nil
        reload()
        if range != .live && !back { spinnerIfSlow() }
    }
    /// The data on screen stays while a new range loads, so the chart cross-fades once; a load slower than 0.5 s shows the spinner.
    private func spinnerIfSlow() {
        let generation = generation
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if generation == self.generation, loading != nil, state == .ready { state = .loading }
        }
    }
    var metric: Metric = .cpu {
        didSet {
            guard metric != oldValue else { return }
            state = .loading
            reload()
        }
    }
    /// Hide Quiet System Processes; on by default. Live rebuilds through `LiveModel.settingsChanged()`.
    var hideQuietSystem = UserDefaults.standard.object(forKey: "hideQuietSystem") as? Bool ?? true {
        didSet {
            guard hideQuietSystem != oldValue else { return }
            UserDefaults.standard.set(hideQuietSystem, forKey: "hideQuietSystem")
            state = .loading
            reload()
        }
    }
    /// Colours the user chose, by app key: each such app gets its own band in every chart. Live picks them up on its
    /// next rebuild.
    var appColors = (UserDefaults.standard.dictionary(forKey: "appColors") as? [String: String] ?? [:])
        .compactMapValues(GroupColor.init(rawValue:)) {
        didSet {
            guard appColors != oldValue else { return }
            UserDefaults.standard.set(appColors.mapValues(\.rawValue), forKey: "appColors")
            restack()
        }
    }
    /// The selected group: only its members are loaded, and the quiet filter is off. Set through `show(_:metric:)`.
    private(set) var scope: ProcessGroup?
    var hidesQuiet: Bool { hideQuietSystem && scope == nil }
    /// Score is a group's metric; Apps shows the recorded ones.
    var metrics: [Metric] { scope == nil ? Metric.recorded : Metric.allCases }
    /// What a Live rebuild depends on, so one change of scope and metric rebuilds Live once.
    var liveSettings: LiveSettings { LiveSettings(metric: metric, scope: scope, hideQuiet: hideQuietSystem) }
    struct LiveSettings: Equatable {
        let metric: Metric
        let scope: ProcessGroup?
        let hideQuiet: Bool
    }
    /// Selected sub-span of the range; `ranking` covers it when set.
    var span: ClosedRange<Double>? { didSet { updateRanking() } }
    private(set) var stacked: [SeriesPoint] = []
    private(set) var ranking: [AppRank] = []
    private(set) var system: [SystemPoint] = []
    private(set) var events: [EventMark] = []
    /// Every app over the whole range (no span): `ranking` while no span is selected.
    private var apps: [AppRank] = []
    private(set) var sparklines: [AppKey: [Double]] = [:]
    /// The apps whose average rose or fell most against the range of the same length before it; nil when that has no data.
    private(set) var changes: (up: [AppChange], down: [AppChange])?
    /// The range before and the 7 days before it, as last read. Both are old, complete data, so a timed reload keeps them
    /// for up to an hour (the hour tier gains rows once an hour); a new range, window, metric, scope or quiet filter reads
    /// them again.
    private var baseline: Baseline?
    private(set) var state: LoadState = .loading
    /// The bundled process glossary, set once it has loaded; nil under `swift run`, which has no bundle resources.
    var glossary: Glossary?
    /// Start of the loaded range: its nominal start, or later when recording began inside it.
    private(set) var start = 0.0

    /// `last_seen` reads as a minute's first tick, and amxd commits every few ticks, so a live process can
    /// look up to a minute plus one commit batch old.
    nonisolated private static let exitSlack = 60 + AMX.tick * Double(AMX.ticksPerCommit + 1) + 5

    private var pool: DatabasePool?
    private var tracks: [ProcessTrack] = []
    /// Indices of `tracks` the quiet filter moved into Other.
    private var hidden: Set<Int> = []
    /// The last hovered bucket's Other breakdown; cleared with each load.
    @ObservationIgnored private var otherCache: OtherCache?
    private(set) var end = 0.0
    /// The chart bucket of the data loaded last: while Live starts, the screen still shows that data.
    private(set) var loadedBucket = HistoryRange.day.chartBucket
    private var generation = 0
    private var requestedAt = 0.0
    private var spanGeneration = 0
    private var loading: Task<Void, Never>?

    /// Runs while a window is open: reload now, then as often as the range's source gains rows while the window ends now
    /// and shows on screen. Checks every 15 s, so a range change (which reloads at once) restarts the interval.
    func run() async {
        reload()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if custom == nil, MainWindowRef.windowShown, Date().timeIntervalSince1970 - requestedAt >= range.source.reloadInterval { reload() }
        }
        loading?.cancel()
    }

    /// Enters, leaves or refreshes a group together with its metric: one load for both.
    func show(_ group: ProcessGroup?, metric: Metric) {
        guard group != scope || metric != self.metric else { return }
        scope = group
        if metric != self.metric {
            self.metric = metric
        } else {
            state = .loading
            reload()
        }
    }

    func reload() {
        loading?.cancel()
        generation += 1
        guard range != .live else { return }
        let (generation, range, metric, scope, hideQuiet, always) = (generation, range, metric, scope, hidesQuiet, Set(appColors.keys))
        let now = Date().timeIntervalSince1970
        let (begin, until) = custom.map { ($0.lowerBound, $0.upperBound) } ?? (now - range.seconds, now)
        requestedAt = now
        let key = (range, custom, metric, scope, hideQuiet)
        let kept = baseline.flatMap { $0.key == key && now - $0.at < 3600 ? $0 : nil }
        if state != .ready { state = .loading }
        let pool: DatabasePool
        do {
            pool = try openPool()
        } catch {
            Self.log.error("cannot open history database: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            return
        }
        loading = Task {
            let result = await Task.detached { () -> Result<Loaded, Error> in
                Result {
                    let reader = HistoryReader(pool: pool)
                    let all = try reader.tracks(source: range.source, from: begin, to: until, metric: metric)
                    let tracks = scope.map { GroupScores.members(all, of: $0) } ?? all
                    let from = AppSeries.recordedStart(all, from: begin)
                    let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: from, to: until) : []
                    let apps = AppSeries.ranking(tracks, from: from, to: until, bucket: range.chartBucket, excluding: hidden,
                                                 exitedBefore: until - Self.exitSlack)
                    let baseline: Baseline
                    if let kept {
                        baseline = kept
                    } else {
                        // The range before, of the same length, ranked as this one is.
                        let earlier = try reader.tracks(source: range.source, from: 2 * begin - until, to: begin, metric: metric)
                        let earlierTracks = scope.map { GroupScores.members(earlier, of: $0) } ?? earlier
                        let earlierFrom = AppSeries.recordedStart(earlier, from: 2 * begin - until)
                        let previous = AppSeries.ranking(earlierTracks, from: earlierFrom, to: begin, bucket: range.chartBucket,
                            excluding: hideQuiet ? QuietFilter.hidden(earlierTracks, metric: metric, from: earlierFrom, to: begin) : [])
                        // At 7D the range before is the same read.
                        let week = range.source == .hour && until - begin == 7 * 86_400 ? earlier
                            : try reader.tracks(source: .hour, from: begin - 7 * 86_400, to: begin, metric: metric)
                        baseline = Baseline(key: key, at: now, previous: earlier.isEmpty ? nil : previous,
                                            profile: UsualProfile(scope.map { GroupScores.members(week, of: $0) } ?? week))
                    }
                    return Loaded(tracks: tracks, hidden: hidden, recorded: !all.isEmpty, start: from,
                           stacked: AppSeries.stacked(tracks, from: from, to: until, bucket: range.chartBucket, always: always, otherOnly: hidden),
                           system: try reader.system(source: range.source, from: begin, to: until, bucket: range.chartBucket),
                           events: try reader.events(from: from, to: until),
                           apps: apps, sparklines: AppSeries.sparklines(tracks, from: from, to: until, excluding: hidden),
                           changes: baseline.previous.map { AppChange.biggest(apps, previous: $0) }, baseline: baseline)
                }
            }.value
            guard generation == self.generation else { return }
            loading = nil
            switch result {
            case .success(let loaded):
                (end, start, loadedBucket) = (until, loaded.start, range.chartBucket)
                (tracks, hidden, otherCache) = (loaded.tracks, loaded.hidden, nil)
                system = loaded.system
                events = loaded.events
                apps = loaded.apps
                sparklines = loaded.sparklines
                (changes, baseline) = (loaded.changes, loaded.baseline)
                stacked = loaded.stacked
                updateRanking()
                // A group without members in the range is ready with no points: "No Activity", not "Collecting".
                state = loaded.recorded ? .ready : .empty
            case .failure(let error):
                Self.log.error("history load: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Only `stacked` uses the chosen colours, so a colour change builds it again from the loaded tracks, off the main
    /// actor; a later load or colour change supersedes it. A load in flight would land with the old colours: it loads again.
    private func restack() {
        guard range != .live, loading == nil else { return reload() }
        generation += 1
        let (generation, tracks, hidden, start, end, bucket, always) =
            (generation, tracks, hidden, start, end, loadedBucket, Set(appColors.keys))
        Task {
            let stacked = await Task.detached {
                AppSeries.stacked(tracks, from: start, to: end, bucket: bucket, always: always, otherOnly: hidden)
            }.value
            if generation == self.generation { self.stacked = stacked }
        }
    }

    /// One app's single series for the range, at chart resolution.
    func series(of app: AppKey) -> [SeriesPoint] {
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: start, to: end, bucket: range.chartBucket)
    }

    /// The hover bubble's largest processes inside Other, for the chart bucket that starts at `bucket`.
    func otherProcesses(bucket: Double, named: Set<AppKey>) -> [(name: String, value: Double)] {
        if let cache = otherCache, cache.bucket == bucket, cache.named == named { return cache.rows }
        let rows = AppSeries.otherProcesses(tracks, named: named, otherOnly: hidden, from: bucket,
                                            to: min(bucket + range.chartBucket, end))
        otherCache = OtherCache(bucket: bucket, named: named, rows: rows)
        return rows
    }

    /// The raw tier over [from, to): Live backfills its first 5 min from the last hour, groups read the last 60 s.
    func rawTracks(metric: Metric, from: Double, to: Double) async throws -> [ProcessTrack] {
        let pool = try openPool()
        return try await Task.detached {
            try HistoryReader(pool: pool).tracks(source: .raw, from: from, to: to, metric: metric)
        }.value
    }

    /// What the glossary says about the selected process, else about the app's main executable (or its first process,
    /// for an app without a bundle). Live has no tracks
    /// here: its process matches by name alone.
    func glossaryEntry(app: AppKey, process: ProcessRank?) -> Glossary.Entry? {
        guard let glossary else { return nil }
        if let process {
            let track = tracks.first { $0.processID == process.processID }
            return glossary.lookup(name: process.name, bundleID: track?.bundleID, path: track?.path)
        }
        let main = tracks.first { $0.app.key == app.key && $0.path?.hasPrefix(app.key + "/Contents/MacOS/") == true }
        return (main ?? tracks.first { $0.app.key == app.key })
            .flatMap { glossary.lookup(name: $0.name, bundleID: $0.bundleID, path: $0.path) }
    }

    func openPool() throws -> DatabasePool {
        if pool == nil { pool = try Store.openReader(path: AMX.databasePath) }
        return pool!
    }

    /// The app's usual value at the hours of day of the span or range; nil with too little history.
    func usual(of app: AppKey) -> Double? {
        baseline?.profile.usual(of: app, from: span?.lowerBound ?? start, to: span?.upperBound ?? end)
    }

    /// The app's process starts and quits in the span or range, newest first.
    func launches(of app: AppKey) -> [LaunchEvent] {
        LaunchEvent.list(tracks.filter { $0.app.key == app.key }, from: span?.lowerBound ?? start, to: span?.upperBound ?? end,
                         exitedBefore: end - Self.exitSlack)
    }

    /// Selects one chart bucket each side of `ts`, inside the range: a launch's or an alert's time on the chart.
    func selectTime(around ts: Double) {
        span = max(start, ts - loadedBucket)...min(end, ts + loadedBucket)
    }

    /// One app's rank for the span or range, from unfiltered tracks: the inspector and pinned views ignore the quiet filter.
    func rank(of app: AppKey) -> AppRank? {
        let from = span?.lowerBound ?? start, to = span?.upperBound ?? end
        return AppSeries.ranking(tracks.filter { $0.app.key == app.key }, from: from, to: to, bucket: range.chartBucket,
                                 exitedBefore: end - Self.exitSlack).first
    }

    /// Without a span the ranking is the range's, built with the load. A span is ranked off the main actor:
    /// up to 22 ms at 24H with the measured churn; a newer span supersedes an older one still ranking.
    private func updateRanking() {
        spanGeneration += 1
        guard let span else { ranking = apps; return }
        let (generation, tracks, bucket, metric, hideQuiet, exitedBefore) =
            (spanGeneration, tracks, range.chartBucket, metric, hidesQuiet, end - Self.exitSlack)
        Task {
            let ranked = await Task.detached {
                // Quiet is judged over the span, the window the ranking covers.
                let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: span.lowerBound, to: span.upperBound) : []
                return AppSeries.ranking(tracks, from: span.lowerBound, to: span.upperBound, bucket: bucket, excluding: hidden,
                                         exitedBefore: exitedBefore)
            }.value
            if generation == spanGeneration { ranking = ranked }
        }
    }

    private struct Loaded: Sendable {
        let tracks: [ProcessTrack]
        let hidden: Set<Int>
        /// The range has data, in the scope or not.
        let recorded: Bool
        let start: Double
        let stacked: [SeriesPoint]
        let system: [SystemPoint]
        let events: [EventMark]
        let apps: [AppRank]
        let sparklines: [AppKey: [Double]]
        let changes: (up: [AppChange], down: [AppChange])?
        let baseline: Baseline
    }

    private struct Baseline: Sendable {
        /// Range, custom window, metric, scope and quiet filter it was read for.
        let key: (HistoryRange, ClosedRange<Double>?, Metric, ProcessGroup?, Bool)
        let at: Double
        /// The range before, ranked; nil when it has no data.
        let previous: [AppRank]?
        /// Each app by hour of day in the 7 days before the range, for `usual(of:)`.
        let profile: UsualProfile
    }
}

/// A hover bubble's Other breakdown: the pointer moves within one bucket many times.
struct OtherCache {
    let bucket: Double
    let named: Set<AppKey>
    let rows: [(name: String, value: Double)]
}

extension HistorySource {
    /// Seconds between reloads: about how often the source gains a row.
    var reloadInterval: Double {
        switch self {
        case .live, .raw: 15
        case .minute: 60
        case .hour: 300
        }
    }
}
