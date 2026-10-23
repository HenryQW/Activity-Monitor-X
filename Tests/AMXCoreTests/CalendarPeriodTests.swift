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

    private func plain(_ totals: [Double?]) -> [CalendarBucket] { totals.map { CalendarBucket(total: $0) } }

    @Test func weekHasSixHourBlocksAndTheLongDayHoldsItsRepeatedHour() {
        let week = CalendarPeriod.week.interval(containing: date(10, 30), calendar: calendar)
        #expect(week.start == date(10, 26) && week.end == date(11, 2))
        let bounds = CalendarPeriod.bounds(week, bucket: 3600, now: .infinity)
        #expect(bounds.count == 7 * 24 + 2)
        let grid = CalendarPeriod.week.grid(week, buckets: plain((0..<(bounds.count - 1)).map { Double($0) }), bucket: 3600, calendar: calendar)
        #expect(grid.count == 4 && grid.allSatisfy { $0.count == 7 })
        // Sunday 1 Nov, 0 to 6 AM: 1 AM happens twice, so its block holds 7 hours (buckets 144 to 150).
        let block = grid[0][6]!
        #expect(block.lines.count == 7 && block.value == 147 && block.end - block.start == 7 * 3600)
        #expect(grid[3][6]!.end == week.end.timeIntervalSince1970 && grid[1][0]!.start == date(10, 26, 6).timeIntervalSince1970)
    }

    @Test func shortDayHasNoSkippedHour() {
        let day = CalendarPeriod.day.interval(containing: date(3, 8, 12), calendar: calendar)
        let bounds = CalendarPeriod.bounds(day, bucket: 3600, now: .infinity)
        #expect(bounds.count == 24)
        let grid = CalendarPeriod.day.grid(day, buckets: plain(Array(repeating: 1, count: 23)), bucket: 3600, calendar: calendar)
        // A row per six hours, a column per hour: 2 AM is row 0, column 2.
        #expect(grid.count == 4 && grid[0].count == 6 && grid[0][2] == nil && grid[0][3]?.value == 1)
    }

    @Test func monthStartsOnFirstWeekdayAndHoursAfterNowHaveNoData() {
        let month = CalendarPeriod.month.interval(containing: date(10, 22), calendar: calendar)
        let now = date(10, 22, 10).timeIntervalSince1970
        let hours = CalendarPeriod.bounds(month, bucket: 3600, now: now)
        #expect(hours.last == now && hours.filter { $0 == now }.count == hours.count - (21 * 24 + 10))
        let totals = (1..<hours.count).map { hours[$0] > hours[$0 - 1] ? 2.0 : nil }
        let grid = CalendarPeriod.month.grid(month, buckets: plain(totals), bucket: 3600, calendar: calendar)
        // 1 Oct 2026 is a Thursday: the fourth column from Monday; 31 days fill 5 weeks.
        #expect(grid.count == 5 && grid[0][2] == nil && grid[0][3]?.start == date(10, 1).timeIntervalSince1970)
        #expect(grid[3][3]?.value == 2 && grid[3][4]?.value == nil && grid[4][5]?.value == nil && grid[4][6] == nil)
        #expect(grid[0][3]?.lines.count == 24)
    }

    @Test func firstWeekdayMovesTheMonthColumns() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let month = CalendarPeriod.month.interval(containing: date(10, 22), calendar: sunday)
        let bounds = CalendarPeriod.bounds(month, bucket: 3600, now: .infinity)
        let grid = CalendarPeriod.month.grid(month, buckets: plain(Array(repeating: 1, count: bounds.count - 1)), bucket: 3600, calendar: sunday)
        #expect(grid[0][4]?.start == date(10, 1).timeIntervalSince1970 && grid[0][3] == nil)
    }

    @Test func zoneMovesTheDayBoundary() {
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 22 Oct 10 PM in New York is 23 Oct 2 AM UTC: another day there.
        let anchor = date(10, 22, 22)
        #expect(CalendarPeriod.day.interval(containing: anchor, calendar: calendar).start == date(10, 22))
        #expect(CalendarPeriod.day.interval(containing: anchor, calendar: utc).start
            == utc.date(from: DateComponents(year: 2026, month: 10, day: 23))!)
    }

    @Test func dayCellsHoldTwelveFiveMinuteLinesAndTheirTopApps() {
        let day = CalendarPeriod.day.interval(containing: date(10, 22), calendar: calendar)
        let a = AppKey(key: "a", name: "a"), b = AppKey(key: "b", name: "b")
        let start = day.start.timeIntervalSince1970
        let bounds = CalendarPeriod.bounds(day, bucket: 300, now: start + 3600)
        // Only the first hour has width: 12 buckets, a at 3 and b at 1, except one bucket with no data.
        var buckets = (0..<(bounds.count - 1)).map { _ in CalendarBucket(total: 4, apps: [a: 3, b: 1]) }
        buckets[11] = CalendarBucket(total: nil)
        let grid = CalendarPeriod.day.grid(day, buckets: buckets, bucket: 300, calendar: calendar)
        let cell = grid[0][0]!
        #expect(cell.lines.count == 12 && cell.lines[11] == nil && cell.value == 4)
        #expect(cell.top == [CellApp(app: a, value: 3), CellApp(app: b, value: 1)])
        #expect(cell.peak == 0 && cell.lineStart(2) == start + 600)
    }

    @Test func bucketsAreFineOnlyInsideTheMinuteTier() {
        let now = date(10, 22).timeIntervalSince1970
        let recent = DateInterval(start: date(10, 20), end: date(10, 21)), old = DateInterval(start: date(8, 1), end: date(8, 2))
        #expect(CalendarPeriod.day.bucket(of: recent, now: now) == 300 && CalendarPeriod.hour.bucket(of: recent, now: now) == 60)
        #expect(CalendarPeriod.day.bucket(of: old, now: now) == 3600 && CalendarPeriod.month.bucket(of: recent, now: now) == 3600)
        #expect(CalendarPeriod.source(bucket: 300) == .minute && CalendarPeriod.source(bucket: 3600) == .hour)
    }

    @Test func rowsAndTheSpanBefore() {
        let month = CalendarPeriod.month.interval(containing: date(10, 22), calendar: calendar)
        let bounds = CalendarPeriod.bounds(month, bucket: 3600, now: .infinity)
        let grid = CalendarPeriod.month.grid(month, buckets: plain((0..<(bounds.count - 1)).map { Double($0 / 24) }), bucket: 3600, calendar: calendar)
        // The first row holds Thu 1 to Sun 4 Oct: values 0 to 3, mean 1.5; its lines are the day values.
        let row = CalendarPeriod.rows(grid)[0]!
        #expect(row.value == 1.5 && row.lines == [nil, nil, nil, 0, 1, 2, 3] && row.start == date(10, 1).timeIntervalSince1970)
        let before = CalendarPeriod.before(start: date(10, 14).timeIntervalSince1970, end: date(10, 16).timeIntervalSince1970, calendar: calendar)
        #expect(before.start == date(10, 12).timeIntervalSince1970 && before.end == date(10, 14).timeIntervalSince1970)
        // Hours are not days: the same seconds back.
        let hours = CalendarPeriod.before(start: date(10, 20, 12).timeIntervalSince1970, end: date(10, 22, 12).timeIntervalSince1970, calendar: calendar)
        #expect(hours.start == date(10, 18, 12).timeIntervalSince1970)
    }

    @Test func stepsStopAtNowAndRetention() {
        let now = date(10, 22, 10)
        #expect(!CalendarPeriod.day.canStep(now, by: 1, now: now, calendar: calendar))
        #expect(CalendarPeriod.day.canStep(now, by: -1, now: now, calendar: calendar))
        let oldest = now.addingTimeInterval(-89 * 86_400)
        #expect(CalendarPeriod.day.canStep(oldest, by: -1, now: now, calendar: calendar))
        #expect(!CalendarPeriod.day.canStep(oldest.addingTimeInterval(-86_400), by: -1, now: now, calendar: calendar))
        #expect(CalendarPeriod.month.canStep(date(9, 30), by: 1, now: now, calendar: calendar))
        #expect(CalendarPeriod.hour.interval(containing: now, calendar: calendar) == DateInterval(start: date(10, 22, 10), duration: 3600))
    }
}
