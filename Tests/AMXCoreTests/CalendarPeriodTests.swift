import Foundation
import Testing
@testable import AMXCore

@Suite struct CalendarPeriodTests {
    /// New York, weeks from Monday: summer time ends on 1 Nov 2026 and starts on 8 Mar 2026.
    private let calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func weekAcrossMonthEndWithLongDay() {
        let week = CalendarPeriod.week.interval(containing: date(10, 30), calendar: calendar)
        #expect(week.start == date(10, 26) && week.end == date(11, 2))
        let hours = CalendarPeriod.hourBounds(week, now: .infinity)
        #expect(hours.count == 7 * 24 + 2)
        let grid = CalendarPeriod.week.grid(week, totals: (0..<(hours.count - 1)).map { Double($0) }, calendar: calendar)
        #expect(grid.count == 24 && grid.allSatisfy { $0.count == 7 })
        // Sunday 1 Nov: 1 AM happens twice, so its cell holds both hours.
        let repeated = grid[1][6]!
        #expect(repeated.end - repeated.start == 7200 && repeated.value == Double(6 * 24 + 1) + 0.5)
        #expect(grid[23][6]!.end == week.end.timeIntervalSince1970)
    }

    @Test func shortDayHasNoSkippedHour() {
        let day = CalendarPeriod.day.interval(containing: date(3, 8, 12), calendar: calendar)
        let hours = CalendarPeriod.hourBounds(day, now: .infinity)
        #expect(hours.count == 24)
        let grid = CalendarPeriod.day.grid(day, totals: Array(repeating: 1, count: 23), calendar: calendar)
        #expect(grid.count == 24 && grid[2][0] == nil && grid[3][0]?.value == 1)
    }

    @Test func monthStartsOnFirstWeekdayAndHoursAfterNowHaveNoData() {
        let month = CalendarPeriod.month.interval(containing: date(10, 22), calendar: calendar)
        let now = date(10, 22, 10).timeIntervalSince1970
        let hours = CalendarPeriod.hourBounds(month, now: now)
        #expect(hours.last == now && hours.filter { $0 == now }.count == hours.count - (21 * 24 + 10))
        let totals = (1..<hours.count).map { hours[$0] > hours[$0 - 1] ? 2.0 : nil }
        let grid = CalendarPeriod.month.grid(month, totals: totals, calendar: calendar)
        // 1 Oct 2026 is a Thursday: the fourth column from Monday; 31 days fill 5 weeks.
        #expect(grid.count == 5 && grid[0][2] == nil && grid[0][3]?.start == date(10, 1).timeIntervalSince1970)
        #expect(grid[3][3]?.value == 2 && grid[3][4]?.value == nil && grid[4][5]?.value == nil && grid[4][6] == nil)
    }

    @Test func stepsStopAtNowAndRetention() {
        let now = date(10, 22, 10)
        #expect(!CalendarPeriod.day.canStep(now, by: 1, now: now, calendar: calendar))
        #expect(CalendarPeriod.day.canStep(now, by: -1, now: now, calendar: calendar))
        let oldest = now.addingTimeInterval(-89 * 86_400)
        #expect(CalendarPeriod.day.canStep(oldest, by: -1, now: now, calendar: calendar))
        #expect(!CalendarPeriod.day.canStep(oldest.addingTimeInterval(-86_400), by: -1, now: now, calendar: calendar))
        #expect(CalendarPeriod.month.canStep(date(9, 30), by: 1, now: now, calendar: calendar))
    }
}
