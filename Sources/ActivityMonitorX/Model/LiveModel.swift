import AMXCore
import Foundation
import Observation

@Observable @MainActor
final class LiveModel {
    private(set) var stacked: [SeriesPoint] = []
    private(set) var ranking: [AppRank] = []
    private(set) var sparklines: [AppKey: [Double]] = [:]
    /// Sparklines cost a second pass per 1 s rebuild, so they are built only while the Apps screen is shown.
    var sparklinesShown = false { didSet { if sparklinesShown { Task { await rebuild() } } } }
    private(set) var state: LoadState = .loading

    private let history: HistoryModel
    let client: DaemonClient
    private var snapshots: [LiveSnapshot] = []
    private var tracks: [ProcessTrack] = []
    private var end = 0.0
    private var generation = 0
    private var failures = 0

    init(history: HistoryModel, client: DaemonClient = DaemonClient()) {
        self.history = history
        self.client = client
    }

    /// Runs while a window is open; polls once a second while the range is Live.
    func run() async {
        while !Task.isCancelled {
            if history.range == .live { await poll() }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Hides data of the old metric or filter and rebuilds from the snapshots at once.
    func settingsChanged() {
        state = .loading
        Task { await rebuild() }
    }

    /// Fetches a snapshot now instead of waiting for the next tick (after a Quit).
    func refresh() async { await poll() }

    private func poll() async {
        do {
            guard let snapshot = try await client.live() else { return }
            failures = 0
            // The daemon repeats its latest snapshot for up to 3 s.
            guard snapshot.ts > (snapshots.last?.ts ?? -.infinity) else { return }
            snapshots.append(snapshot)
            snapshots.removeAll { $0.ts <= snapshot.ts - 300 }
            await rebuild()
        } catch {
            // One missed poll keeps the last data; only a lasting outage shows the error.
            failures += 1
            if failures >= 3 { state = .failed(error.localizedDescription) }
        }
    }

    /// Builds off the main actor; a newer rebuild supersedes an older one still running.
    private func rebuild() async {
        guard let last = snapshots.last else { return }
        generation += 1
        let (generation, snapshots, metric, hideQuiet, withSparklines) =
            (generation, snapshots, history.metric, history.hideQuietSystem, sparklinesShown)
        let end = last.ts + 1
        let built = await Task.detached {
            let tracks = LiveTracks.build(snapshots, metric: metric)
            let hidden = hideQuiet ? QuietFilter.hidden(tracks, metric: metric, from: end - 300, to: end) : []
            return (tracks: tracks,
                    stacked: AppSeries.stacked(tracks, from: end - 300, to: end, bucket: 1, otherOnly: hidden),
                    ranking: AppSeries.ranking(tracks, from: end - 300, to: end, bucket: 1, excluding: hidden, exitedBefore: last.ts),
                    sparklines: withSparklines ? AppSeries.sparklines(tracks, from: end - 300, to: end, excluding: hidden) : [:])
        }.value
        guard generation == self.generation else { return }
        (self.end, tracks, stacked, ranking, sparklines) = (end, built.tracks, built.stacked, built.ranking, built.sparklines)
        // A rebuild during an outage must not hide the error.
        if failures < 3 { state = .ready }
    }

    /// One app's rank for the last 5 min, unfiltered (see `HistoryModel.rank(of:)`).
    func rank(of app: AppKey) -> AppRank? {
        AppSeries.ranking(tracks.filter { $0.app.key == app.key }, from: end - 300, to: end, bucket: 1,
                          exitedBefore: end - 1).first
    }

    /// One app's single series for the last 5 min.
    func series(of app: AppKey) -> [SeriesPoint] {
        AppSeries.stacked(tracks.filter { $0.app.key == app.key }, from: end - 300, to: end, bucket: 1)
    }
}
