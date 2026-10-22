import Foundation

/// Each app's typical value by hour of day over a past window (hour tier): what the inspector's "Compared to Usual"
/// compares a range against.
public struct UsualProfile: Sendable {
    /// Days from the first to the last recorded slice; under 2 the profile gives no usual value.
    public let days: Double
    private let calendar: Calendar
    /// Seconds of recorded time per hour of day: a gap in an app's slices inside it counts as 0.
    private let seconds: [Double]
    /// Each app's value × seconds per hour of day.
    private let sums: [AppKey: [Double]]

    public init(_ tracks: [ProcessTrack], calendar: Calendar = .current) {
        let first = tracks.compactMap { $0.slices.first?.start }.min() ?? 0
        let last = tracks.compactMap { $0.slices.last?.end }.max() ?? 0
        var seconds = Array(repeating: 0.0, count: 24), sums: [AppKey: [Double]] = [:]
        Self.hours(from: first, to: last, calendar: calendar) { seconds[$0] += $1 }
        for track in tracks {
            var row = sums[track.app] ?? Array(repeating: 0, count: 24)
            for slice in track.slices {
                Self.hours(from: slice.start, to: slice.end, calendar: calendar) { row[$0] += slice.value * $1 }
            }
            sums[track.app] = row
        }
        (days, self.calendar, self.seconds, self.sums) = ((last - first) / 86_400, calendar, seconds, sums)
    }

    /// The app's usual mean at the hours of day of [from, to), each hour weighted by its time there; nil with under
    /// 2 days of history or none at those hours. An app absent from the history is usually 0.
    public func usual(of app: AppKey, from: Double, to: Double) -> Double? {
        guard days >= 2 else { return nil }
        let row = sums[app] ?? Array(repeating: 0, count: 24)
        var total = 0.0, weight = 0.0
        Self.hours(from: from, to: to, calendar: calendar) { hour, s in
            guard seconds[hour] > 0 else { return }
            (total, weight) = (total + s * row[hour] / seconds[hour], weight + s)
        }
        return weight > 0 ? total / weight : nil
    }

    /// "2.4× usual", "About usual" within 0.8 to 1.25 times, or "Usually idle at these hours".
    public static func describe(_ value: Double, usual: Double, locale: Locale = .current) -> String {
        guard usual > 0 else { return value > 0 ? "Usually idle at these hours" : "About usual" }
        let ratio = value / usual
        if (0.8...1.25).contains(ratio) { return "About usual" }
        return "\(ratio.formatted(.number.precision(.significantDigits(1...2)).locale(locale)))× usual"
    }

    /// Calls `body` with the hour of day and the seconds of each whole-hour step of [from, to).
    private static func hours(from: Double, to: Double, calendar: Calendar, _ body: (Int, Double) -> Void) {
        var t = from
        while t < to {
            let next = min(((t / 3600).rounded(.down) + 1) * 3600, to)
            body(calendar.component(.hour, from: Date(timeIntervalSince1970: t)), next - t)
            t = next
        }
    }
}

/// An app's average in a range against the range of the same length before it.
public struct AppChange: Sendable, Identifiable {
    public var id: String { app.key }
    public let app: AppKey
    public let now: Double
    public let before: Double
    public var delta: Double { now - before }

    /// The `count` apps whose average rose most, and the `count` whose average fell most; an app absent from one
    /// window counts 0 there.
    public static func biggest(_ current: [AppRank], previous: [AppRank], count: Int = 3) -> (up: [AppChange], down: [AppChange]) {
        var pairs: [AppKey: (now: Double, before: Double)] = [:]
        for rank in current { pairs[rank.app, default: (0, 0)].now = rank.average }
        for rank in previous { pairs[rank.app, default: (0, 0)].before = rank.average }
        let all = pairs.map { AppChange(app: $0.key, now: $0.value.now, before: $0.value.before) }
            .sorted { ($1.delta, $0.app.key) < ($0.delta, $1.app.key) }
        return (Array(all.filter { $0.delta > 0 }.prefix(count)), Array(all.filter { $0.delta < 0 }.reversed().prefix(count)))
    }
}

/// A process start or quit inside a window.
public struct LaunchEvent: Sendable, Identifiable {
    public var id: String { "\(processID) \(isQuit)" }
    public let ts: Double
    public let processID: Int64
    public let pid: Int32
    public let name: String
    public let isQuit: Bool

    /// Each process's start when in [from, to), and its quit (the end of its last slice) when in [from, to) and the
    /// process was gone before `exitedBefore`; newest first. A process alive at the window's end has no quit.
    public static func list(_ tracks: [ProcessTrack], from: Double, to: Double, exitedBefore: Double) -> [LaunchEvent] {
        tracks.flatMap { track -> [LaunchEvent] in
            var events: [LaunchEvent] = []
            if track.startTime >= from && track.startTime < to {
                events.append(LaunchEvent(ts: track.startTime, processID: track.processID, pid: track.pid, name: track.name, isQuit: false))
            }
            if track.lastSeen < exitedBefore, let end = track.slices.last?.end, end >= from && end < to {
                events.append(LaunchEvent(ts: end, processID: track.processID, pid: track.pid, name: track.name, isQuit: true))
            }
            return events
        }
        .sorted { ($1.ts, $1.processID, $1.isQuit ? 1 : 0) < ($0.ts, $0.processID, $0.isQuit ? 1 : 0) }
    }
}
