import Foundation

public enum AgentError: Error, Equatable, CustomStringConvertible {
    case unknownTool(String), invalid(String)

    public var description: String {
        switch self {
        case .unknownTool(let name): "unknown tool: \(name)"
        case .invalid(let message): message
        }
    }
}

/// A time window and the history tier that answers it with at most 120 chart points.
public struct QueryWindow: Sendable, Equatable {
    public let from: Double
    public let to: Double
    public let source: HistorySource
    public let bucket: Double

    public static func resolve(from: Double, to: Double, now: Double) throws -> QueryWindow {
        guard to > from else { throw AgentError.invalid("from must be before to") }
        let span = to - from
        let (source, step): (HistorySource, Double)
        if from >= now - 86_400 && span <= 21_600 {
            (source, step) = (.raw, 5)
        } else if from >= now - 2_592_000 && span <= 604_800 {
            (source, step) = (.minute, 60)
        } else {
            (source, step) = (.hour, 3600)
        }
        return QueryWindow(from: from, to: to, source: source, bucket: max(step, (span / 120 / step).rounded(.up) * step))
    }
}

public enum TimeArg {
    /// `now`, `-<n>s|m|h|d`, Unix seconds, or ISO 8601 with `Z` or an offset.
    public static func parse(_ text: String, now: Double) throws -> Double {
        if text == "now" { return now }
        if text.hasPrefix("-"), let unit = text.last, let n = Double(text.dropFirst().dropLast()),
           let seconds = ["s": 1.0, "m": 60, "h": 3600, "d": 86_400][String(unit)], (now - n * seconds).isFinite {
            return now - n * seconds
        }
        if let seconds = Double(text), seconds.isFinite { return seconds }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return date.timeIntervalSince1970 }
        }
        throw AgentError.invalid("bad time: \(text)")
    }
}
