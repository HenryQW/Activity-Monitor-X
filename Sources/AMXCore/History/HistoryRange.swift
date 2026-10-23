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

extension HistoryRange {
    /// The smallest stored range longer than a window of `length` seconds; nil from the widest.
    public static func wider(than length: Double) -> HistoryRange? {
        allCases.dropFirst().first { $0.seconds > length }
    }

    /// The largest stored range shorter than a window of `length` seconds; nil from the narrowest.
    public static func narrower(than length: Double) -> HistoryRange? {
        allCases.dropFirst().last { $0.seconds < length }
    }

    /// A window of `length` seconds around the middle of `window`, moved back to end by `now` at the latest.
    public func window(around window: ClosedRange<Double>, now: Double) -> ClosedRange<Double> {
        let end = min((window.lowerBound + window.upperBound + seconds) / 2, now)
        return (end - seconds)...end
    }
}
