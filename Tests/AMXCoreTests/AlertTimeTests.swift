import Foundation
import Testing
@testable import AMXCore

struct AlertTimeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let locale = Locale(identifier: "en_US")

    private func ts(daysAgo: Int, _ hour: Int, _ minute: Int) -> Double {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!.timeIntervalSince1970
    }

    @Test func relativeDaysInTheLocale() {
        #expect(AlertTime.format(ts(daysAgo: 0, 10, 42), calendar: calendar, locale: locale).hasPrefix("Today"))
        #expect(AlertTime.format(ts(daysAgo: 0, 10, 42), calendar: calendar, locale: locale).contains("10:42"))
        #expect(AlertTime.format(ts(daysAgo: 1, 23, 10), calendar: calendar, locale: locale).hasPrefix("Yesterday"))
        #expect(AlertTime.format(ts(daysAgo: 400, 9, 5), calendar: calendar, locale: locale).contains("9:05"))
    }
}
