import Foundation

public enum HistorySource: Sendable { case live, raw, minute, hour }

public enum HistoryRange: CaseIterable, Sendable {
    case live, hour, day, week, month, quarter

    public var seconds: Double {
        switch self {
        case .live: 300
        case .hour: 3600
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        case .quarter: 7_776_000
        }
    }

    public var source: HistorySource {
        switch self {
        case .live: .live
        case .hour: .raw
        case .day: .minute
        case .week, .month, .quarter: .hour
        }
    }

    /// Chart bucket width in seconds.
    public var chartBucket: Double {
        switch self {
        case .live: 1
        case .hour: 15
        case .day: 300
        case .week: 3600
        case .month: 14_400
        case .quarter: 43_200
        }
    }
}

extension HistoryRange {
    /// The subtitle when recording began inside the range, in the locale's formats: "Since 11:06 PM" today,
    /// "Since Yesterday, 11:06 PM", and the day only from 7D up ("Since 21 Oct"). The Range button names the range.
    public func since(_ start: Double, now: Double, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = Date(timeIntervalSince1970: start)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date(timeIntervalSince1970: now))).day!
        let daysOnly = seconds >= HistoryRange.week.seconds
        // Up to 24H the start is today or yesterday.
        var style = daysOnly ? Date.FormatStyle.dateTime.day().month(.abbreviated) : .dateTime.hour().minute()
        (style.calendar, style.timeZone, style.locale) = (calendar, calendar.timeZone, locale)
        return "Since \(!daysOnly && days > 0 ? "Yesterday, " : "")\(date.formatted(style))"
    }
}

extension HistoryRange {
    /// The range whose source and chart bucket serve a custom window: the smallest that covers its length and whose
    /// tier still keeps its start. Quarter when none does. Live is not stored.
    public static func covering(from: Double, to: Double, now: Double) -> HistoryRange {
        allCases.dropFirst().first { $0.seconds >= to - from && now - from <= $0.kept } ?? .quarter
    }

    /// How long the range's tier keeps rows.
    private var kept: Double {
        let policy = RetentionPolicy()
        switch source {
        case .live: return 0
        case .raw: return policy.raw
        case .minute: return policy.minute
        case .hour: return policy.hour
        }
    }
}
