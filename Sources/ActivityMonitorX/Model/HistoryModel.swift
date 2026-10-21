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
    /// Start of the loaded range: its nominal start, or later when recording began inside it.
    private(set) var start = 0.0
    /// `start` when recording began more than one chart bucket into the range, for the subtitle.
    private(set) var since: Double?

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

    func reload() {
        loading?.cancel()
        generation += 1
        guard range != .live else { return }
        let (generation, range, metric, hideQuiet, now) = (generation, range, metric, hideQuietSystem, Date().timeIntervalSince1970)
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
                    let tracks = try reader.tracks(range: range, metric: metric, end: now)
                    let from = AppSeries.recordedStart(tracks, from: now - range.seconds)
                    let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: from, to: now) : []
                    return Loaded(tracks: tracks, start: from,
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
                state = tracks.isEmpty ? .empty : .ready
            case .failure(let error):
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// One app's single series for the range, at chart resolution.
    func series(of app: AppKey) -> [SeriesPoint] {
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: start, to: end, bucket: range.chartBucket)
    }

    /// The raw tier's last hour before `end`; Live backfills its first 5 min from it.
    func rawTracks(metric: Metric, end: Double) async throws -> [ProcessTrack] {
        let pool = try openPool()
        return try await Task.detached { try HistoryReader(pool: pool).tracks(range: .hour, metric: metric, end: end) }.value
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
            (spanGeneration, tracks, range.chartBucket, metric, hideQuietSystem, end - Self.exitSlack)
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
