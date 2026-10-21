import Foundation
import Testing
@testable import AMXCore

private func event(_ kind: String, _ severity: Int, _ message: String) -> EventMark {
    EventMark(ts: 0, kind: kind, severity: severity, message: message, app: nil)
}

@Test func nearEventsClusterUnderTheMostSevere() {
    let clusters = EventClusters.clusters([
        (x: 0, event: event("pressure", 0, "normal")), (x: 5, event: event("pressure", 1, "warn")),
        (x: 11, event: event("thermal", 3, "critical")), (x: 12, event: event("pressure", 1, "next")),
        (x: 40, event: event("thermal", 1, "fair")), (x: 60, event: event("other", 2, "unshown")),
    ], gap: 12)
    // [0, 12) is one marker led by the critical event; 12 starts the next; the lone info event at 40 has none.
    #expect(clusters.map(\.x) == [0, 12])
    #expect(clusters[0].events.map(\.message) == ["normal", "warn", "critical"])
    #expect(clusters[0].lead.message == "critical")
    #expect(clusters[1].lead.message == "next")
}

@Test func sinceNamesTodayYesterdayOrTheDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let us = Locale(identifier: "en_US"), gb = Locale(identifier: "en_GB")
    let now = 1_792_641_600.0  // 2026-10-22 04:00 UTC
    func since(_ range: HistoryRange, _ start: Double, _ locale: Locale) -> String {
        range.since(start, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
    }
    #expect(since(.hour, now - 2 * 3600 - 54 * 60, us) == "Since 1:06 AM")
    #expect(since(.day, now - 4 * 3600 - 54 * 60, us) == "Since Yesterday, 11:06 PM")
    #expect(since(.week, now - 4 * 3600 - 54 * 60, us) == "Since Oct 21")
    #expect(since(.week, now - 4 * 3600 - 54 * 60, gb) == "Since 21 Oct")
}
