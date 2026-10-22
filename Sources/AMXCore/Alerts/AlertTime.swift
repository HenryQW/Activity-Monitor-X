import Foundation

/// The Alerts Time column in the user's locale: relative day words where the locale has them ("Today at 10:42 AM"),
/// else the short date and time.
public enum AlertTime {
    public static func format(_ ts: Double, calendar: Calendar = .current, locale: Locale = .current) -> String {
        formatter(calendar, locale).string(from: Date(timeIntervalSince1970: ts))
    }

    /// Formatters are costly and the table redraws: one per calendar, zone and locale.
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    private static func formatter(_ calendar: Calendar, _ locale: Locale) -> DateFormatter {
        let key = "\(calendar.identifier)|\(calendar.timeZone.identifier)|\(locale.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        cache[key] = f
        return f
    }
}
