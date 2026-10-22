import AMXCore
import Foundation
import GRDB
import Observation

enum LoadState: Equatable {
    case loading, empty, ready
    case failed(String)
}

@Observable @MainActor
final class HistoryModel {
    var range: HistoryRange = .day {
        didSet {
            guard range != oldValue else { return }
            span = nil
            since = nil
            state = .loading
            reload()
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
    /// The selected group: only its members are loaded, and the quiet filter is off. Set through `show(_:metric:)`.
    private(set) var scope: ProcessGroup?
    var hidesQuiet: Bool { hideQuietSystem && scope == nil }
    /// Score is a group's metric; the Timeline shows the recorded ones.
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
    /// Every app over the whole range (no span), with its sparkline, for the Apps screen.
    private(set) var apps: [AppRank] = []
    private(set) var sparklines: [AppKey: [Double]] = [:]
    private(set) var state: LoadState = .loading
    /// The bundled process glossary, set once it has loaded; nil under `swift run`, which has no bundle resources.
    var glossary: Glossary?
    /// Start of the loaded range: its nominal start, or later when recording began inside it.
    private(set) var start = 0.0
    /// `start` when recording began more than one chart bucket into the range.
    private var since: Double?
    /// "Since …" when recording began inside the range, else empty: the Range pop-up names the range. Live has none.
    var subtitle: String { since.map { range.since($0, now: end) } ?? "" }

    /// `last_seen` reads as a minute's first tick, and amxd commits every few ticks, so a live process can
    /// look up to a minute plus one commit batch old.
    nonisolated private static let exitSlack = 60 + AMX.tick * Double(AMX.ticksPerCommit + 1) + 5

    private var pool: DatabasePool?
    private var tracks: [ProcessTrack] = []
    private var end = 0.0
    private var generation = 0
    private var requestedAt = 0.0
    private var spanGeneration = 0
    private var loading: Task<Void, Never>?

    /// Runs while a window is open: reload now, then as often as the range's source gains rows. Checks every
    /// 15 s, so a range change (which reloads at once) restarts the interval.
    func run() async {
        reload()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if Date().timeIntervalSince1970 - requestedAt >= range.source.reloadInterval { reload() }
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
        let (generation, range, metric, scope, hideQuiet) = (generation, range, metric, scope, hidesQuiet)
        let now = Date().timeIntervalSince1970
        requestedAt = now
        if state != .ready { state = .loading }
        let pool: DatabasePool
        do {
            pool = try openPool()
        } catch {
            state = .failed("Cannot open history database: \(error.localizedDescription)")
            return
        }
        loading = Task {
            let result = await Task.detached { () -> Result<Loaded, Error> in
                Result {
                    let reader = HistoryReader(pool: pool)
                    let all = try reader.tracks(range: range, metric: metric, end: now)
                    let tracks = scope.map { GroupScores.members(all, of: $0) } ?? all
                    let from = AppSeries.recordedStart(all, from: now - range.seconds)
                    let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: from, to: now) : []
                    return Loaded(tracks: tracks, recorded: !all.isEmpty, start: from,
                           stacked: AppSeries.stacked(tracks, from: from, to: now, bucket: range.chartBucket, otherOnly: hidden),
                           system: try reader.system(range: range, end: now),
                           events: try reader.events(from: from, to: now),
                           apps: AppSeries.ranking(tracks, from: from, to: now, bucket: range.chartBucket, excluding: hidden,
                                                   exitedBefore: now - Self.exitSlack),
                           sparklines: AppSeries.sparklines(tracks, from: from, to: now, excluding: hidden))
                }
            }.value
            guard generation == self.generation else { return }
            switch result {
            case .success(let loaded):
                (end, start) = (now, loaded.start)
                since = start - (now - range.seconds) > range.chartBucket ? start : nil
                tracks = loaded.tracks
                system = loaded.system
                events = loaded.events
                apps = loaded.apps
                sparklines = loaded.sparklines
                stacked = loaded.stacked
                updateRanking()
                // A group without members in the range is ready with no points: "No Activity", not "Collecting".
                state = loaded.recorded ? .ready : .empty
            case .failure(let error):
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// One app's single series for the range, at chart resolution.
    func series(of app: AppKey) -> [SeriesPoint] {
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: start, to: end, bucket: range.chartBucket)
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

    private func openPool() throws -> DatabasePool {
        if pool == nil { pool = try Store.openReader(path: AMX.databasePath) }
        return pool!
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
        /// The range has data, in the scope or not.
        let recorded: Bool
        let start: Double
        let stacked: [SeriesPoint]
        let system: [SystemPoint]
        let events: [EventMark]
        let apps: [AppRank]
        let sparklines: [AppKey: [Double]]
    }
}

private extension HistorySource {
    /// Seconds between reloads: about how often the source gains a row.
    var reloadInterval: Double {
        switch self {
        case .live, .raw: 15
        case .minute: 60
        case .hour: 300
        }
    }
}
