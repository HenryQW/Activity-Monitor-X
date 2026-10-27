import Foundation

/// An app's mean value inside a Calendar cell.
public struct CellApp: Sendable, Equatable {
    public let app: AppKey
    public let value: Double
}

/// One cell of the Calendar: a day (Month), a six-hour block (Week), an hour (Day) or the hour itself (Hour).
public struct CalendarCell: Sendable, Equatable {
    /// The time the cell covers; Apps opens on it.
    public let start: Double
    public let end: Double
    /// The mean of its buckets' totals that have data; nil when none has.
    public let value: Double?
    /// The buckets inside, in time order, nil where one has no data: an hour each in Month and Week, five minutes in Day,
    /// a minute in Hour (an hour each past the minute tier's retention). Their width is `bucket`.
    public let lines: [Double?]
    public let bucket: Double
    /// The apps with the largest means, at most 5, largest first.
    public let top: [CellApp]
    /// The busiest app of each line, as `lines`.
    public let leaders: [CellApp?]
    /// The mean of the recorded processes' sum; lower than `value` where that is the Mac's CPU (CB1). nil in a row cell.
    public var recorded: Double? = nil

    /// The start of line `index`.
    public func lineStart(_ index: Int) -> Double { start + Double(index) * bucket }

    /// The index of the highest line, nil when none has data.
    public var peak: Int? {
        lines.indices.filter { lines[$0] != nil }.max { lines[$0]! < lines[$1]! }
    }
}

/// What the Calendar shows at once: a month of days, a week of six-hour blocks, a day of hours, or an hour of minutes.
/// The period strip offers Day, Week and Month; Hour is reached by zooming in.
public enum CalendarPeriod: String, CaseIterable, Sendable {
    case day, week, month, hour

    /// The periods the strip offers.
    public static let strip: [CalendarPeriod] = [.day, .week, .month]

    private var component: Calendar.Component {
        switch self {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// The period a double-click on a cell opens: Month to Week to Day to Hour.
    public var zoomedIn: CalendarPeriod? {
        switch self {
        case .month: .week
        case .week: .day
        case .day: .hour
        case .hour: nil
        }
    }

    public var zoomedOut: CalendarPeriod? {
        switch self {
        case .hour: .day
        case .day: .week
        case .week: .month
        case .month: nil
        }
    }

    /// The period that holds `date`; a week starts on the calendar's first weekday.
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }

    public func step(_ date: Date, by steps: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: steps, to: date)!
    }

    /// Whether the period `steps` away can hold history: it starts by `now` and ends after the hour tier's retention.
    public func canStep(_ date: Date, by steps: Int, now: Date, calendar: Calendar,
                        kept: TimeInterval = RetentionPolicy().hour) -> Bool {
        let target = interval(containing: step(date, by: steps, calendar: calendar), calendar: calendar)
        return target.start <= now && target.end > now.addingTimeInterval(-kept)
    }

    /// The seconds of a bucket: an hour for Month and Week, five minutes for Day, a minute for Hour, from the minute tier;
    /// an interval that starts before that tier's retention has the hour tier only, so an hour.
    public func bucket(of interval: DateInterval, now: Double, minuteKept: TimeInterval = RetentionPolicy().minute) -> Double {
        let fine: Double = self == .day ? 300 : 60
        guard self == .day || self == .hour else { return 3600 }
        return interval.start.timeIntervalSince1970 < now - minuteKept ? 3600 : fine
    }

    /// The tier that holds buckets of `bucket` seconds.
    public static func source(bucket: Double) -> HistorySource { bucket < 3600 ? .minute : .hour }

    /// The bucket starts of `interval` and its end, none later than `now`, so a bucket after `now` has no width. Local hours
    /// are 3600 s apart across a DST change too.
    public static func bounds(_ interval: DateInterval, bucket: Double, now: Double) -> [Double] {
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        return (Array(stride(from: start, to: end, by: bucket)) + [end]).map { min($0, now) }
    }

    /// The cells as rows of columns, from the `buckets` of `interval` (as `bounds`). Month: a row per week, a column per
    /// weekday from the first weekday, nil outside the month. Week: a row per six hours of the day, a column per day. Day:
    /// a row per six hours, a column per hour of the row. Hour: one cell. The repeated hour of a 25-hour day lands in the
    /// cell of its hour of day, so that cell holds both; the skipped hour of a 23-hour day has no buckets (a Day cell for it
    /// is nil).
    public func grid(_ interval: DateInterval, buckets: [CalendarBucket], bucket: Double, calendar: Calendar) -> [[CalendarCell?]] {
        struct Sum {
            var start: Double, end: Double, sum = 0.0, count = 0
            var lines: [Double?] = [], leaders: [CellApp?] = [], apps: [AppKey: Double] = [:]
        }
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day!
        let lead = self == .month ? (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7 : 0
        let (rows, columns) = switch self {
        case .month: ((lead + days + 6) / 7, 7)
        case .week: (4, 7)
        case .day: (4, 6)
        case .hour: (1, 1)
        }
        var cells = [[Sum?]](repeating: [Sum?](repeating: nil, count: columns), count: rows)
        for (i, b) in buckets.enumerated() {
            let from = start + Double(i) * bucket, to = min(from + bucket, end), date = Date(timeIntervalSince1970: from)
            let hour = calendar.component(.hour, from: date)
            let day = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: date)).day!
            let (row, column) = switch self {
            case .month: ((lead + day) / 7, (lead + day) % 7)
            case .week: (hour / 6, day)
            case .day: (hour / 6, hour % 6)
            case .hour: (0, 0)
            }
            var cell = cells[row][column] ?? Sum(start: from, end: to)
            cell.end = to
            cell.lines.append(b.total)
            cell.leaders.append(b.apps.max { ($0.value, $1.key.key) < ($1.value, $0.key.key) }.map { CellApp(app: $0.key, value: $0.value) })
            if let total = b.total {
                cell.sum += total
                cell.count += 1
                for (app, value) in b.apps { cell.apps[app, default: 0] += value }
            }
            cells[row][column] = cell
        }
        return cells.map { row in
            row.map { cell in
                cell.map { cell in
                    let top = cell.apps.map { CellApp(app: $0.key, value: $0.value / Double(cell.count)) }
                        .sorted { ($1.value, $0.app.key) < ($0.value, $1.app.key) }
                    return CalendarCell(start: cell.start, end: cell.end, value: cell.count > 0 ? cell.sum / Double(cell.count) : nil,
                                        lines: cell.lines, bucket: bucket, top: Array(top.prefix(5)), leaders: cell.leaders,
                                        recorded: cell.count > 0 ? cell.apps.values.reduce(0, +) / Double(cell.count) : nil)
                }
            }
        }
    }

    /// The cells of `grid` in time order.
    public static func ordered(_ grid: [[CalendarCell?]]) -> [CalendarCell] {
        grid.joined().compactMap { $0 }.sorted { $0.start < $1.start }
    }

    /// One cell per row of `grid` (Month: the week; Week: the six-hour block of every day), holding the mean of all the
    /// row's buckets that have data and, as lines, the row's cells' values. nil for a row with no cell.
    public static func rows(_ grid: [[CalendarCell?]]) -> [CalendarCell?] {
        grid.map { row in
            let cells = row.compactMap { $0 }
            guard let first = cells.first, let last = cells.last else { return nil }
            let values = cells.flatMap(\.lines).compactMap { $0 }
            return CalendarCell(start: first.start, end: last.end, value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                                lines: row.map { $0?.value }, bucket: 0, top: [], leaders: [])
        }
    }

    /// The span of the same length that ends where [start, end) starts: whole days back for a span of whole days, else the
    /// same seconds.
    public static func before(start: Double, end: Double, calendar: Calendar) -> (start: Double, end: Double) {
        let from = Date(timeIntervalSince1970: start), to = Date(timeIntervalSince1970: end)
        if calendar.startOfDay(for: from) == from, calendar.startOfDay(for: to) == to,
           let days = calendar.dateComponents([.day], from: from, to: to).day,
           let back = calendar.date(byAdding: .day, value: -days, to: from) {
            return (back.timeIntervalSince1970, start)
        }
        return (start - (end - start), start)
    }
}
