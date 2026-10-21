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

    /// `last_seen` is written once a minute, so a process unseen for 70 s has exited.
    nonisolated private static let exitSlack = 70.0

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
        do {
            if pool == nil { pool = try Store.openReader(path: AMX.databasePath) }
        } catch {
            state = .failed("Cannot open history database: \(error.localizedDescription)")
            return
        }
        let pool = pool!
        loading = Task {
            let result = await Task.detached { () -> Result<Loaded, Error> in
                Result {
                    let reader = HistoryReader(pool: pool)
                    let tracks = try reader.tracks(range: range, metric: metric, end: now)
                    let from = now - range.seconds
                    let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: from, to: now) : []
                    return Loaded(tracks: tracks,
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
                end = now
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
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: end - range.seconds, to: end, bucket: range.chartBucket)
    }

    /// One app's rank for the span or range, from unfiltered tracks: the inspector and pinned views ignore the quiet filter.
    func rank(of app: AppKey) -> AppRank? {
        let from = span?.lowerBound ?? end - range.seconds, to = span?.upperBound ?? end
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
