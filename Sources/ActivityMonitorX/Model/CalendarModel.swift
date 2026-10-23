import AMXCore
import Foundation
import GRDB
import Observation
import os

/// What the cells list besides their value: the busiest app of each, or nothing, or the use of one group alone.
enum CalendarShow: Hashable {
    case busiest, all
    case group(UUID)

    var stored: String {
        switch self {
        case .busiest: "busiest"
        case .all: "all"
        case .group(let id): id.uuidString
        }
    }

    init(stored: String?) {
        self = switch stored {
        case "all": .all
        case let text?: UUID(uuidString: text).map(CalendarShow.group) ?? .busiest
        case nil: .busiest
        }
    }
}

/// What a load keeps of the history: the apps a search matches, and the members of the shown group.
struct CalendarFilter: Equatable, Sendable {
    var query = ""
    var group: ProcessGroup?

    func keeps(_ tracks: [ProcessTrack]) -> [ProcessTrack] {
        let found = query.isEmpty ? tracks : tracks.filter { AppSearch.matches($0.app, query) }
        return group.map { GroupScores.members(found, of: $0) } ?? found
    }
}

/// One loaded period: the cells with what they were read for, so a frame before the next load never mixes the two.
struct CalendarPage {
    let period: CalendarPeriod
    let interval: DateInterval
    let metric: Metric
    let filter: CalendarFilter
    /// Rows of columns, as `CalendarPeriod.grid`, and the Week column's cell of each row.
    let grid: [[CalendarCell?]]
    let rows: [CalendarCell?]
    /// What colours the metric (the system CPU rule's levels, the recorded memory pressure); nil where it has none.
    let status: CalendarStatus?
    /// The alerts in the period (rows with a rule), in time order.
    let alerts: [EventMark]
    let calendar: Calendar
    let bucket: Double

    /// The highest line of any cell, at least a quarter over the warning level, so cells compare on one axis.
    var top: Double {
        let highest = grid.joined().compactMap { $0 }.flatMap(\.lines).compactMap { $0 }.max() ?? 0
        return max(highest, (status?.warn ?? 0) * 1.25, 1)
    }

    var cells: [CalendarCell] { CalendarPeriod.ordered(grid) }

    /// The apps of the cells' top lists, the most often listed first: the ones that get colours.
    var apps: [AppKey] {
        var counts: [AppKey: Int] = [:]
        for cell in cells { for entry in cell.top { counts[entry.app, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key.key) < ($0.value, $1.key.key) }.map(\.key)
    }

    /// The buckets of `cells` at the warning and at the critical level.
    func counts(_ cells: [CalendarCell]) -> (warning: Int, critical: Int) { status?.counts(cells) ?? (0, 0) }

    /// The CPU levels as dashed lines: only for every app, as with a search or a group the lines are a subset of the Mac.
    var levels: CalendarStatus? { filter.query.isEmpty && filter.group == nil ? status : nil }

    /// The severity of each line of `cell`; empty with no status.
    func severities(_ cell: CalendarCell) -> [Int?] { status?.severities(cell) ?? [] }

    /// A row cell's lines are its cells' values: the highest severity among the buckets of each of those cells.
    func severities(row: Int) -> [Int?] {
        guard let status else { return [] }
        return grid[row].map { $0.flatMap { status.severities($0).compactMap { $0 }.max() } }
    }

    /// How a count of buckets is worded: CPU is over a line, memory is at a pressure level.
    func phrase(_ level: String) -> String { status?.warn == nil ? "at \(level) pressure" : "over the \(level) line" }

    var hoursLabel: String { status?.warn == nil ? "Hours at pressure" : "Hours over a line" }

    func alerts(in cell: CalendarCell) -> [EventMark] { alerts.filter { cell.start <= $0.ts && $0.ts < cell.end } }
}

/// A span set against the span of the same length before it.
struct CalendarComparison: Sendable {
    let before: (start: Double, end: Double)
    let now: SpanStats
    let then: SpanStats
    let change: (up: [AppChange], down: [AppChange])
}

/// The Calendar screen: one period's cells, each the metric summed over all apps for a day, a block of hours, an hour or a
/// minute span, from the hour or the minute tier.
@Observable @MainActor
final class CalendarModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "calendar")
    private static let periodKey = "calendarPeriod", showKey = "calendarShow"

    /// The period shown; Hour is reached by zooming and kept as Day.
    var period = CalendarPeriod(rawValue: UserDefaults.standard.string(forKey: CalendarModel.periodKey) ?? "") ?? .week {
        didSet { UserDefaults.standard.set((period == .hour ? .day : period).rawValue, forKey: Self.periodKey) }
    }
    var show = CalendarShow(stored: UserDefaults.standard.string(forKey: CalendarModel.showKey)) {
        didSet { UserDefaults.standard.set(show.stored, forKey: Self.showKey) }
    }
    /// A time inside the shown period; Today sets it to now.
    var anchor = Date()
    private(set) var page: CalendarPage?
    private(set) var state: LoadState = .loading
    /// The starts of the first and last selected cell, in time order; one cell has both the same. In Day and Hour the
    /// cells hold bars (a line each) and these are the starts of the first and last selected bar. A period without them
    /// shows none.
    var selected: ClosedRange<Double>?
    /// The periods left by zooming in, with their anchor and selection, for Back.
    private var trail: [(period: CalendarPeriod, anchor: Date, selected: ClosedRange<Double>?)] = []
    /// The usual total by weekday and hour; nil until read, and with too little history.
    private(set) var usual: CalendarUsual?

    /// The cells of the selection, in time order.
    var selectedCells: [CalendarCell] {
        guard let selected, let page, !page.period.selectsBars else { return [] }
        return page.cells.filter { selected.contains($0.start) }
    }

    /// The one selected cell with data, or nil for none or a span. With bars, the cell that holds the first selected bar.
    var selectedCell: CalendarCell? {
        if let selected, let page, page.period.selectsBars {
            return page.cells.first { $0.start <= selected.lowerBound && selected.lowerBound < $0.end && $0.value != nil }
        }
        let cells = selectedCells
        return cells.count == 1 && cells[0].value != nil ? cells[0] : nil
    }

    private let history: HistoryModel
    /// The alert rules of the last load, for a comparison.
    private var rules = AlertRules()
    private var generation = 0
    private var usualGeneration = 0
    private var usualKey: String?
    private var usualAt = Date.distantPast

    init(history: HistoryModel) { self.history = history }

    var calendar: Calendar { AppTime.calendar }

    var interval: DateInterval { period.interval(containing: anchor, calendar: calendar) }

    func canStep(_ steps: Int) -> Bool { period.canStep(anchor, by: steps, now: Date(), calendar: calendar) }

    func step(_ steps: Int) { anchor = period.step(anchor, by: steps, calendar: calendar) }

    /// Selects the cells from the one starting at `low` to the one starting at `high`; with a `base` (shift), the span that
    /// also holds it.
    func select(_ low: Double, _ high: Double, extending base: ClosedRange<Double>? = nil) {
        selected = base.map { min($0.lowerBound, low)...max($0.upperBound, high) } ?? low...high
    }

    /// Opens the finer period that starts at `start` (a click twice on a cell); nothing at Hour.
    func zoomIn(at start: Double) {
        guard let deeper = period.zoomedIn else { return }
        open(deeper, at: start)
    }

    /// Opens `period` around `start`, for example the hour of a line.
    func open(_ period: CalendarPeriod, at start: Double) {
        trail.append((self.period, anchor, selected))
        (anchor, self.period, selected) = (Date(timeIntervalSince1970: start), period, nil)
    }

    /// Back to the wider period; nothing at Month. It restores the period, anchor and selection that were left, if the
    /// shown period is still inside them, else it opens the wider period around the one shown.
    func zoomOut() {
        guard let wider = period.zoomedOut else { return }
        if let left = trail.popLast(), left.period == wider, wider.interval(containing: left.anchor, calendar: calendar).contains(anchor) {
            (anchor, period, selected) = (left.anchor, wider, left.selected)
        } else {
            trail.removeAll()
            (period, selected) = (wider, nil)
        }
    }

    /// The wider period's name for the Back button: "October", "Week of 20 Oct", "Thu 22"; nil at Month.
    var widerName: String? {
        guard let wider = period.zoomedOut else { return nil }
        let start = wider.interval(containing: anchor, calendar: calendar).start
        return switch wider {
        case .month: start.formatted(.dateTime.month(.wide))
        case .week: "Week of " + start.formatted(.dateTime.day().month(.abbreviated))
        default: start.formatted(.dateTime.weekday(.abbreviated).day())
        }
    }

    /// The screen's task, started again for each period, metric and filter: loads now, then as often as the hour tier gains
    /// rows while the window shows on screen. A new search keeps the shown cells and waits for typing to pause.
    func run(metric: Metric, filter: CalendarFilter, rules: AlertRules) async {
        if let page, page.interval == interval, page.metric == metric {
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
        } else {
            state = .loading
        }
        await load(metric: metric, filter: filter, rules: rules)
        await loadUsual(metric: metric, filter: filter)
        var loadedAt = Date()
        // Checks each minute, so a window shown again catches up within a minute.
        while (try? await Task.sleep(for: .seconds(60))) != nil {
            guard MainWindowRef.windowShown, -loadedAt.timeIntervalSinceNow >= HistorySource.hour.reloadInterval else { continue }
            await load(metric: metric, filter: filter, rules: rules)
            await loadUsual(metric: metric, filter: filter)
            loadedAt = Date()
        }
    }

    /// Reads off the main actor; a newer load supersedes an older one still reading.
    func load(metric: Metric, filter: CalendarFilter, rules: AlertRules) async {
        self.rules = rules
        generation += 1
        let (generation, period, interval, calendar, now) = (generation, period, interval, calendar, Date().timeIntervalSince1970)
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
                let reader = HistoryReader(pool: pool)
                var bucket = period.bucket(of: interval, now: now)
                var bounds = CalendarPeriod.bounds(interval, bucket: bucket, now: now)
                var tracks = try reader.tracks(source: CalendarPeriod.source(bucket: bucket), from: bounds[0], to: bounds[bounds.count - 1],
                                               metric: metric)
                // The size cap can delete minute rows before their retention ends: the hour tier then serves the period.
                if bucket < 3600, tracks.isEmpty {
                    bucket = 3600
                    bounds = CalendarPeriod.bounds(interval, bucket: bucket, now: now)
                    tracks = try reader.tracks(source: .hour, from: bounds[0], to: bounds[bounds.count - 1], metric: metric)
                }
                let grid = period.grid(interval, buckets: CalendarBucket.read(filter.keeps(tracks), bounds: bounds), bucket: bucket,
                                       calendar: calendar)
                let status = try reader.calendarStatus(metric: metric, rules: rules, source: CalendarPeriod.source(bucket: bucket),
                                                       from: bounds[0], to: bounds[bounds.count - 1], bucket: bucket)
                let events = try reader.events(from: bounds[0], to: bounds[bounds.count - 1]).filter { $0.rule != nil }
                return CalendarPage(period: period, interval: interval, metric: metric, filter: filter, grid: grid,
                                    rows: CalendarPeriod.rows(grid), status: status,
                                    alerts: events, calendar: calendar, bucket: bucket)
            }
        }.value
        guard generation == self.generation else { return }
        switch result {
        case .success(let page):
            self.page = page
            state = page.grid.joined().contains { $0?.value != nil } ? .ready : .empty
        case .failure(let error):
            Self.log.error("calendar load: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// The usual total by weekday and hour of the filter's apps over the hour tier's retention, read again after an hour.
    private func loadUsual(metric: Metric, filter: CalendarFilter) async {
        let key = "\(metric.rawValue) \(filter.query) \(filter.group?.id.uuidString ?? "") \(AppTime.zone.identifier) \(calendar.firstWeekday)"
        guard key != usualKey || -usualAt.timeIntervalSinceNow > 3600, let pool = try? history.openPool() else { return }
        usualGeneration += 1
        let (generation, calendar, now) = (usualGeneration, calendar, Date().timeIntervalSince1970)
        let value = await Task.detached { () -> CalendarUsual? in
            let start = ((now - RetentionPolicy().hour) / 3600).rounded(.up) * 3600
            let bounds = Array(stride(from: start, through: now, by: 3600))
            guard bounds.count > 1,
                  let tracks = try? HistoryReader(pool: pool).tracks(source: .hour, from: start, to: now, metric: metric) else { return nil }
            let totals = CalendarBucket.read(filter.keeps(tracks), bounds: bounds).map(\.total)
            return CalendarUsual(totals: totals, start: start, calendar: calendar)
        }.value
        // A read for another metric or filter started since: its answer owns `usual`.
        guard generation == usualGeneration else { return }
        (usual, usualKey, usualAt) = (value, key, Date())
    }

    /// The apps the filter keeps, by their average over [from, to) from the first record up to now, from the tier of `bucket`;
    /// nil when the read fails.
    func apps(from: Double, to: Double, metric: Metric, filter: CalendarFilter, bucket: Double = 3600) async -> [AppRank]? {
        guard let pool = try? history.openPool() else { return nil }
        let (start, end) = (from, min(to, Date().timeIntervalSince1970))
        guard end > start else { return [] }
        return await Task.detached {
            let tracks = try? HistoryReader(pool: pool).tracks(source: CalendarPeriod.source(bucket: bucket), from: start, to: end, metric: metric)
            return tracks.map { tracks in
                // Recorded time only, as Apps ranks: a period's hours before recording began are not idle time.
                let from = AppSeries.recordedStart(tracks, from: start)
                return AppSeries.ranking(filter.keeps(tracks), from: from, to: end, bucket: end - from)
            }
        }.value
    }

    /// [start, end) set against the span of the same length before it, from the hour tier; nil when the read fails.
    func compare(start: Double, end: Double, metric: Metric, filter: CalendarFilter) async -> CalendarComparison? {
        guard let pool = try? history.openPool() else { return nil }
        let (before, calendar, now, rules) = (CalendarPeriod.before(start: start, end: end, calendar: calendar), calendar, Date().timeIntervalSince1970, rules)
        return await Task.detached {
            let reader = HistoryReader(pool: pool)
            guard let tracks = try? reader.tracks(source: .hour, from: before.start, to: min(end, now), metric: metric) else {
                return nil
            }
            let kept = filter.keeps(tracks)
            func stats(_ from: Double, _ to: Double) throws -> SpanStats {
                let bounds = CalendarPeriod.bounds(DateInterval(start: Date(timeIntervalSince1970: from), end: Date(timeIntervalSince1970: to)), bucket: 3600, now: now)
                let hours = CalendarBucket.read(kept, bounds: bounds).map(\.total)
                let status = try reader.calendarStatus(metric: metric, rules: rules, source: .hour, from: bounds[0],
                                                       to: bounds[bounds.count - 1], bucket: 3600)
                return SpanStats(hours: hours, start: from, status: status, calendar: calendar)
            }
            func ranking(_ from: Double, _ to: Double) -> [AppRank] {
                let first = AppSeries.recordedStart(kept, from: from), last = min(to, now)
                return last > first ? AppSeries.ranking(kept, from: first, to: last, bucket: last - first) : []
            }
            let change = AppChange.biggest(ranking(start, end), previous: ranking(before.start, before.end))
            guard let now = try? stats(start, end), let then = try? stats(before.start, before.end) else { return nil }
            return CalendarComparison(before: before, now: now, then: then, change: change)
        }.value
    }
}
