import Foundation

/// One cell of the Calendar: an hour (Day, Week) or a day (Month).
public struct CalendarCell: Sendable, Equatable {
    /// The time the cell covers; Apps opens on it.
    public let start: Double
    public let end: Double
    /// The mean of its hours' totals that have data; nil when none has.
    public let value: Double?
}

/// What the Calendar shows at once: a day or a week of hours, or a month of days.
public enum CalendarPeriod: String, CaseIterable, Sendable {
    case day, week, month

    private var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
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

    /// The hour starts of `interval` and its end, none later than `now`, so an hour after `now` has no width. Local hours are
    /// 3600 s apart across a DST change too.
    public static func hourBounds(_ interval: DateInterval, now: Double) -> [Double] {
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        return (Array(stride(from: start, to: end, by: 3600)) + [end]).map { min($0, now) }
    }

    /// The cells as rows of columns, from `totals` of each hour of `interval` (as `hourBounds`). Day and Week: a row per
    /// hour of the day, a column per day; the repeated hour of a 25-hour day holds both hours, the skipped hour of a
    /// 23-hour day is nil. Month: a row per week, a column per weekday from the first weekday; nil outside the month.
    public func grid(_ interval: DateInterval, totals: [Double?], calendar: Calendar) -> [[CalendarCell?]] {
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day!
        let lead = self == .month ? (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7 : 0
        let columns = self == .day ? 1 : 7, rows = self == .month ? (lead + days + 6) / 7 : 24
        var cells: [[(start: Double, end: Double, sum: Double, count: Int)?]] =
            Array(repeating: Array(repeating: nil, count: columns), count: rows)
        for (i, total) in totals.enumerated() {
            let from = start + Double(i) * 3600, to = min(from + 3600, end), date = Date(timeIntervalSince1970: from)
            let day = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: date)).day!
            let (row, column) = self == .month ? ((lead + day) / 7, (lead + day) % 7) : (calendar.component(.hour, from: date), day)
            let cell = cells[row][column] ?? (from, to, 0, 0)
            cells[row][column] = (cell.start, to, cell.sum + (total ?? 0), cell.count + (total == nil ? 0 : 1))
        }
        return cells.map { row in
            row.map { $0.map { CalendarCell(start: $0.start, end: $0.end, value: $0.count > 0 ? $0.sum / Double($0.count) : nil) } }
        }
    }
}
