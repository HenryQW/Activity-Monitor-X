import AMXCore
import Foundation
import GRDB
import Observation
import os

/// One loaded period: the cells with what they were read for, so a frame before the next load never mixes the two.
struct CalendarPage {
    let period: CalendarPeriod
    let interval: DateInterval
    let metric: Metric
    /// The search the cells were read for: each cell then sums the matching apps only.
    let query: String
    /// Rows of columns, as `CalendarPeriod.grid`.
    let grid: [[CalendarCell?]]
}

/// The Calendar screen: one period's cells, each the metric summed over all apps for an hour or a day, from the hour tier.
@Observable @MainActor
final class CalendarModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "calendar")
    private static let periodKey = "calendarPeriod"

    var period = CalendarPeriod(rawValue: UserDefaults.standard.string(forKey: CalendarModel.periodKey) ?? "") ?? .week {
        didSet { UserDefaults.standard.set(period.rawValue, forKey: Self.periodKey) }
    }
    /// A time inside the shown period; Today sets it to now.
    var anchor = Date()
    private(set) var page: CalendarPage?
    private(set) var state: LoadState = .loading
    /// The start of the cell the inspector shows; a period without it shows none.
    var selected: Double?

    var selectedCell: CalendarCell? {
        guard let selected else { return nil }
        return page?.grid.joined().lazy.compactMap { $0 }.first { $0.start == selected }
    }

    private let history: HistoryModel
    private var generation = 0

    init(history: HistoryModel) { self.history = history }

    var interval: DateInterval { period.interval(containing: anchor, calendar: .current) }

    func canStep(_ steps: Int) -> Bool { period.canStep(anchor, by: steps, now: Date(), calendar: .current) }

    func step(_ steps: Int) { anchor = period.step(anchor, by: steps, calendar: .current) }

    /// The screen's task, started again for each period, metric and search: loads now, then as often as the hour tier gains
    /// rows while the window shows on screen. A new search keeps the shown cells and waits for typing to pause.
    func run(metric: Metric, query: String) async {
        if let page, page.interval == interval, page.metric == metric {
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
        } else {
            state = .loading
        }
        await load(metric: metric, query: query)
        var loadedAt = Date()
        // Checks each minute, so a window shown again catches up within a minute.
        while (try? await Task.sleep(for: .seconds(60))) != nil {
            guard MainWindowRef.windowShown, -loadedAt.timeIntervalSinceNow >= HistorySource.hour.reloadInterval else { continue }
            await load(metric: metric, query: query)
            loadedAt = Date()
        }
    }

    /// Reads off the main actor; a newer load supersedes an older one still reading.
    func load(metric: Metric, query: String) async {
        generation += 1
        let (generation, period, interval, now) = (generation, period, interval, Date().timeIntervalSince1970)
        let pool: DatabasePool
        do {
            pool = try history.openPool()
        } catch {
            Self.log.error("cannot open history database: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            return
        }
        let result = await Task.detached {
            Result {
                let totals = try HistoryReader(pool: pool).totals(metric: metric, bounds: CalendarPeriod.hourBounds(interval, now: now),
                                                                  query: query)
                return period.grid(interval, totals: totals, calendar: .current)
            }
        }.value
        guard generation == self.generation else { return }
        switch result {
        case .success(let grid):
            page = CalendarPage(period: period, interval: interval, metric: metric, query: query, grid: grid)
            state = grid.joined().contains { $0?.value != nil } ? .ready : .empty
        case .failure(let error):
            Self.log.error("calendar load: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// The apps of `cell` matching `query`, by their average over its time (up to now), from the hour tier; nil when the
    /// read fails.
    func apps(in cell: CalendarCell, metric: Metric, query: String) async -> [AppRank]? {
        guard let pool = try? history.openPool() else { return nil }
        let (start, end) = (cell.start, min(cell.end, Date().timeIntervalSince1970))
        guard end > start else { return [] }
        return await Task.detached {
            let tracks = try? HistoryReader(pool: pool).tracks(source: .hour, from: start, to: end, metric: metric)
            return tracks.map { tracks in
                AppSeries.ranking(tracks.filter { query.isEmpty || AppSearch.matches($0.app, query) },
                                  from: start, to: end, bucket: end - start)
            }
        }.value
    }
}
