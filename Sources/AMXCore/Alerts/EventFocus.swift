import Foundation

extension AlertRules {
    /// The rule's own window in seconds; an alert is stamped at the end of its spell (M4-D15).
    public func lookback(rule: String) -> Double {
        switch rule {
        case RuleName.sustainedCPU: Double(sustainedCPU.minutes * 60)
        case RuleName.memoryGrowth: Double(memoryGrowth.minutes * 60)
        case RuleName.systemCPU: Double(systemCPU.minutes * 60)
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

/// Where Apps opens for an alert or a Calendar cell.
public enum EventFocus {
    private static let after = 300.0

    /// The alert's spell to 5 min after the alert.
    public static func window(for ts: Double, lookback: Double, now: Double)
        -> (range: HistoryRange, span: ClosedRange<Double>?) {
        window(from: ts - lookback, to: ts + after, now: now)
    }

    /// The smallest range that holds `start`, and the span from there to `end`, clamped to the range (nil when empty).
    public static func window(from start: Double, to end: Double, now: Double)
        -> (range: HistoryRange, span: ClosedRange<Double>?) {
        let range = [HistoryRange.hour, .day, .week, .month].first { now - $0.seconds <= start } ?? .quarter
        let from = max(start, now - range.seconds), to = min(end, now)
        return (range, from <= to ? from...to : nil)
    }
}
