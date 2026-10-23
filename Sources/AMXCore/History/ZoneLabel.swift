import Foundation

/// How a time zone reads in a pop-up: its abbreviation, and when it is not system time, how far it is from system time.
public enum ZoneLabel {
    /// The zones the pop-up lists first, to force or to add as hour labels.
    public static let common = ["UTC", "Asia/Tokyo", "Europe/London", "America/New_York", "America/Los_Angeles"]

    /// Standard and summer abbreviations: the system names many of these "GMT+9".
    private static let names: [String: (standard: String, summer: String)] = [
        "UTC": ("UTC", "UTC"), "GMT": ("UTC", "UTC"), "Asia/Hong_Kong": ("HKT", "HKT"), "Asia/Tokyo": ("JST", "JST"),
        "Asia/Seoul": ("KST", "KST"), "Asia/Singapore": ("SGT", "SGT"), "Asia/Kolkata": ("IST", "IST"), "Asia/Dubai": ("GST", "GST"),
        "Europe/London": ("GMT", "BST"), "Europe/Paris": ("CET", "CEST"), "Europe/Berlin": ("CET", "CEST"),
        "America/New_York": ("EST", "EDT"), "America/Chicago": ("CST", "CDT"), "America/Denver": ("MST", "MDT"),
        "America/Los_Angeles": ("PST", "PDT"), "Australia/Sydney": ("AEST", "AEDT"),
    ]

    /// "HKT", "PDT"; a zone without a short name reads "GMT+9".
    public static func abbreviation(_ zone: TimeZone, at date: Date) -> String {
        let summer = zone.isDaylightSavingTime(for: date)
        if let name = names[zone.identifier] { return summer ? name.summer : name.standard }
        return zone.localizedName(for: summer ? .shortDaylightSaving : .shortStandard, locale: Locale(identifier: "en_US")) ?? zone.identifier
    }

    /// "15 h behind" or "1 h ahead" of `system` at `date`; nil when the two have the same offset.
    public static func difference(of zone: TimeZone, from system: TimeZone, at date: Date) -> String? {
        let hours = Double(zone.secondsFromGMT(for: date) - system.secondsFromGMT(for: date)) / 3600
        guard hours != 0 else { return nil }
        return "\(abs(hours).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))) h \(hours < 0 ? "behind" : "ahead")"
    }

    /// The pop-up's label: "HKT" for system time, "PDT, 15 h behind" for a forced zone that is not the system's.
    public static func title(forced: TimeZone?, system: TimeZone, at date: Date) -> String {
        guard let forced else { return abbreviation(system, at: date) }
        return [abbreviation(forced, at: date), difference(of: forced, from: system, at: date)].compactMap { $0 }.joined(separator: ", ")
    }
}
