import Foundation

extension AlertRules {
    /// The rule's own window in seconds; an alert is stamped at the end of its spell (M4-D15).
    public func lookback(rule: String) -> Double {
        switch rule {
        case RuleName.sustainedCPU: Double(sustainedCPU.minutes * 60)
        case RuleName.memoryGrowth: Double(memoryGrowth.minutes * 60)
        case RuleName.thermal: Double(thermal.minutes * 60)
        case RuleName.memoryJump: 50
        case RuleName.diskWrites: 3600
        case RuleName.network: Double(network.minutes * 60)
        case RuleName.energy: Double(energy.minutes * 60)
        case RuleName.gpu: Double(gpu.minutes * 60)
        default: 600
        }
    }
}

/// Where Apps opens for an alert.
public enum EventFocus {
    private static let after = 300.0

    /// The smallest range that holds the start of the alert's spell, and the span from there to 5 min after
    /// the alert, clamped to the range (nil when empty).
    public static func window(for ts: Double, lookback: Double, now: Double)
        -> (range: HistoryRange, span: ClosedRange<Double>?) {
        let start = ts - lookback
        let range = [HistoryRange.hour, .day, .week, .month].first { now - $0.seconds <= start } ?? .quarter
        let from = max(start, now - range.seconds), to = min(ts + after, now)
        return (range, from <= to ? from...to : nil)
    }
}
