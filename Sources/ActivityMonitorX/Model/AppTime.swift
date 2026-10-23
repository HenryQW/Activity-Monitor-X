import AMXCore
import Foundation

/// The time zone and first weekday every screen uses: the system's unless the user forces one (the Calendar's zone pop-up)
/// or picks a weekday (Settings). `Preferences` keeps and sets them; dates and day boundaries read them from here.
enum AppTime {
    nonisolated(unsafe) private(set) static var forced: TimeZone?
    nonisolated(unsafe) private(set) static var firstWeekday: Int?

    static let system = TimeZone.autoupdatingCurrent
    static var zone: TimeZone { forced ?? system }

    /// The system calendar in `zone`, from the chosen first weekday. Day, week and month boundaries come from it.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = zone
        if let firstWeekday { calendar.firstWeekday = firstWeekday }
        return calendar
    }

    /// The abbreviation of the zone, with its difference from system time when one is forced.
    static func title(of zone: TimeZone?, at date: Date = Date()) -> String {
        ZoneLabel.title(forced: zone, system: system, at: date)
    }

    /// The hour of `time` in `zone`, as the system writes hours ("6 PM"); the shown zone's formats go through `formatted`.
    static func hour(_ time: Double, in zone: TimeZone) -> String {
        var style = Date.FormatStyle().hour()
        style.timeZone = zone
        return style.format(Date(timeIntervalSince1970: time))
    }

    /// An x axis label in the app's zone: the Charts default follows the system zone. Times for a span up to two days, else dates.
    static func axisFormat(seconds: Double) -> Date.FormatStyle {
        let style = Date.FormatStyle(timeZone: zone)
        return seconds <= 2 * 86_400 ? style.hour().minute() : style.month(.abbreviated).day()
    }

    /// "6 PM HKT".
    static func namedHour(_ time: Double, in zone: TimeZone) -> String {
        "\(hour(time, in: zone)) \(ZoneLabel.abbreviation(zone, at: Date(timeIntervalSince1970: time)))"
    }

    static func apply(zoneID: String?, firstWeekday: Int?) {
        forced = zoneID.flatMap(TimeZone.init(identifier:))
        self.firstWeekday = firstWeekday
        // Calendar.current and DateFormatter follow the default zone; `formatted` follows `zone` (below).
        NSTimeZone.default = zone
    }

    /// A system zone change (travel, System Settings) reaches `NSTimeZone.default` only through this: the cached system zone
    /// is reset and the default set again; `changed` then tells the views to draw again.
    static func followSystemChanges(changed: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { _ in
            NSTimeZone.resetSystemTimeZone()
            apply(zoneID: forced?.identifier, firstWeekday: firstWeekday)
            MainActor.assumeIsolated(changed)
        }
    }
}

extension Date {
    /// `formatted` in the app's time zone: this overload, in the app's module, is the one a call with a date style picks.
    func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = AppTime.zone
        return style.format(self)
    }

    func formatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time))
    }
}

extension Range<Date> {
    /// The interval formats ("1:12 to 1:40 AM") in the app's time zone.
    func formatted(_ style: Date.IntervalFormatStyle) -> String {
        var style = style
        style.timeZone = AppTime.zone
        return style.format(self)
    }
}
