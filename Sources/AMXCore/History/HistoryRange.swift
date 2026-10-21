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
