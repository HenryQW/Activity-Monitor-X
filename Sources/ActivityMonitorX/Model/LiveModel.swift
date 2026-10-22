import AMXCore
import Foundation
import Observation
import os

@Observable @MainActor
final class LiveModel {
    private(set) var stacked: [SeriesPoint] = []
    private(set) var ranking: [AppRank] = []
    private(set) var sparklines: [AppKey: [Double]] = [:]
    /// Sparklines cost a second pass per 1 s rebuild, so they are built only while the Apps screen is shown.
    var sparklinesShown = false { didSet { if sparklinesShown { rankedAt = -.infinity; Task { await rebuild() } } } }
    private(set) var state: LoadState = .loading

    private static let log = Logger(subsystem: AMX.bundleID, category: "live")
    private let history: HistoryModel
    private let selection: Selection
    let client: DaemonClient
    /// This visit's tracks, from its snapshots and the raw history before them.
    private var live = LiveTracks(metric: .cpu)
    /// `live` scoped to the group, as last built.
    private var tracks: [ProcessTrack] = []
    /// Indices of `tracks` the quiet filter moved into Other.
    private var hidden: Set<Int> = []
    /// The last hovered bucket's Other breakdown; cleared with each rebuild.
    @ObservationIgnored private var otherCache: OtherCache?
    private var end = 0.0
    /// Start of recorded time in the 5 min window: averages cover it only; the chart keeps the full 5 min.
    private var start = 0.0
    /// The `end` of the last ranking: the table gets a new one every 5 s, the chart every second.
    private var rankedAt = -Double.infinity
    private var generation = 0
    private var failures = 0

    init(history: HistoryModel, selection: Selection, client: DaemonClient = DaemonClient()) {
        self.history = history
        self.selection = selection
        self.client = client
    }

    /// Runs while a window is open; polls once a second while the range is Live, a window shows on screen and the screen
    /// shows app data (a System screen reads its own data and must not wake amxd every second). Each
    /// visit to Live, and each return to the screen, starts afresh, so the backfill covers the time away.
    func run() async {
        while !Task.isCancelled {
            if history.range == .live, !selection.isSystem, MainWindowRef.windowShown { await poll() } else { live = LiveTracks(metric: history.metric) }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Hides data of the old metric or filter and rebuilds at once; a new metric first loads its backfill.
    func settingsChanged() {
        state = .loading
        rankedAt = -.infinity
        Task {
            if live.metric != history.metric { await loadBackfill() }
            await rebuild()
        }
    }

    /// Without the history database Live still works; it then opens with only its own snapshots. After 5 min in Live
    /// the raw history ends before the window, so it is not read.
    private func loadBackfill() async {
        guard let first = live.start, let latest = live.latest else { return }
        let metric = history.metric
        let raw = latest + 1 - 300 >= first ? []
            : (try? await history.rawTracks(metric: metric, from: first - HistoryRange.hour.seconds, to: first)) ?? []
        // A metric change or a new visit during the read loads its own backfill.
        guard metric == history.metric, first == live.start, let latest = live.latest else { return }
        live.reset(metric: metric, raw: raw, from: latest + 1 - 300)
    }

    /// Fetches a snapshot now instead of waiting for the next tick (after a Quit).
    func refresh() async { await poll() }

    private func poll() async {
        do {
            guard let snapshot = try await client.live() else { return }
            Self.log.debug("live poll: \(snapshot.processes.count) processes")
            failures = 0
            // The daemon repeats its latest snapshot for up to 3 s.
            guard snapshot.ts > (live.latest ?? -.infinity) else { return }
            let first = live.latest == nil
            if first { live = LiveTracks(metric: history.metric) }
            live.append(snapshot)
            live.trim(before: snapshot.ts + 1 - 300)
            if first { await loadBackfill() }
            await rebuild()
        } catch {
            // One missed poll keeps the last data; only a lasting outage shows the error.
            failures += 1
            if failures == 3 { Self.log.error("live poll: \(error.localizedDescription, privacy: .public)") }
            if failures >= 3 { state = .failed(error.localizedDescription) }
        }
    }

    /// Builds off the main actor; a newer rebuild supersedes an older one still running. Waits while a new metric's
    /// backfill loads.
    private func rebuild() async {
        guard let last = live.latest, live.metric == history.metric else { return }
        generation += 1
        let end = last + 1
        let withRanking = end - rankedAt >= 5
        let (generation, all, metric, scope, hideQuiet, withSparklines) =
            (generation, live.tracks, live.metric, history.scope, history.hidesQuiet, sparklinesShown)
        let built = await Task.detached {
            let tracks = scope.map { GroupScores.members(all, of: $0) } ?? all
            let from = AppSeries.recordedStart(all, from: end - 300)
            let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: from, to: end) : []
            return (tracks: tracks, hidden: hidden, start: from,
                    stacked: AppSeries.stacked(tracks, from: end - 300, to: end, bucket: 1, otherOnly: hidden),
                    ranking: withRanking ? AppSeries.ranking(tracks, from: from, to: end, bucket: 1, excluding: hidden, exitedBefore: last) : [],
                    sparklines: withRanking && withSparklines ? AppSeries.sparklines(tracks, from: from, to: end, excluding: hidden) : [:])
        }.value
        guard generation == self.generation else { return }
        (self.end, start, tracks, hidden, stacked) = (end, built.start, built.tracks, built.hidden, built.stacked)
        otherCache = nil
        if withRanking { (rankedAt, ranking, sparklines) = (end, built.ranking, built.sparklines) }
        // A rebuild during an outage must not hide the error.
        if failures < 3 { state = .ready }
    }

    /// One app's rank for the last 5 min, unfiltered (see `HistoryModel.rank(of:)`).
    func rank(of app: AppKey) -> AppRank? {
        AppSeries.ranking(tracks.filter { $0.app.key == app.key }, from: start, to: end, bucket: 1,
                          exitedBefore: end - 1).first
    }

    /// The hover bubble's largest processes inside Other, for the 1 s bucket that starts at `bucket`.
    func otherProcesses(bucket: Double, named: Set<AppKey>) -> [(name: String, value: Double)] {
        if let cache = otherCache, cache.bucket == bucket, cache.named == named { return cache.rows }
        let rows = AppSeries.otherProcesses(tracks, named: named, otherOnly: hidden, from: bucket, to: min(bucket + 1, end))
        otherCache = OtherCache(bucket: bucket, named: named, rows: rows)
        return rows
    }

    /// One app's single series for the last 5 min.
    func series(of app: AppKey) -> [SeriesPoint] {
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: end - 300, to: end, bucket: 1)
    }
}
