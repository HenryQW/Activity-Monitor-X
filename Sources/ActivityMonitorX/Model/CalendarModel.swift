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

    private let history: HistoryModel
    private var generation = 0

    init(history: HistoryModel) { self.history = history }

    var interval: DateInterval { period.interval(containing: anchor, calendar: .current) }

    func canStep(_ steps: Int) -> Bool { period.canStep(anchor, by: steps, now: Date(), calendar: .current) }

    func step(_ steps: Int) { anchor = period.step(anchor, by: steps, calendar: .current) }

    /// The screen's task, started again for each period and metric: loads now, then once a minute.
    func run(metric: Metric) async {
        state = .loading
        while !Task.isCancelled {
            await load(metric: metric)
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Reads off the main actor; a newer load supersedes an older one still reading.
    func load(metric: Metric) async {
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
                let totals = try HistoryReader(pool: pool).totals(metric: metric, bounds: CalendarPeriod.hourBounds(interval, now: now))
                return period.grid(interval, totals: totals, calendar: .current)
            }
        }.value
        guard generation == self.generation else { return }
        switch result {
        case .success(let grid):
            page = CalendarPage(period: period, interval: interval, metric: metric, grid: grid)
            state = grid.joined().contains { $0?.value != nil } ? .ready : .empty
        case .failure(let error):
            Self.log.error("calendar load: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
