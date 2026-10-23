import Foundation
import Testing
@testable import AMXCore

@Suite struct CalendarBucketsTests {
    private let utc = { () -> Calendar in
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func track(_ name: String, _ slices: [(Double, Double, Double)]) -> ProcessTrack {
        ProcessTrack(processID: 1, pid: 1, startTime: 0, name: name, app: AppKey(key: name, name: name),
                     slices: slices.map { Slice(start: $0.0, end: $0.1, value: $0.2) })
    }

    @Test func bucketsSumAppsAndKeepGapsAsNoData() {
        let tracks = [track("a", [(0, 3600, 10)]), track("b", [(1800, 7200, 20)])]
        let buckets = CalendarBucket.read(tracks, bounds: [0, 3600, 7200, 10_800, 10_800])
        // Hour 0: a for all of it, b for half. Hour 1: b only. Nothing after, and a bucket of no width.
        #expect(buckets[0].total == 20 && buckets[0].apps[AppKey(key: "b", name: "b")] == 10)
        #expect(buckets[1].total == 20 && buckets[1].apps.count == 1)
        #expect(buckets[2].total == nil && buckets[3].total == nil)
    }

    @Test func statusFollowsTheRulesForCPUAndPressureForMemory() throws {
        let device = Device(cores: 10, memory: 100)
        var rules = AlertRules()
        // 70 % and 90 % of all cores, in % of one core.
        // The level comes from each bucket's machine CPU, so the apps shown (a subset) do not change it.
        let cpu = try #require(CalendarStatus(metric: .cpu, rules: rules, device: device, cpu: [0: 69, 3600: 70, 7200: 90, 10_800: 95]))
        #expect(cpu.warn == 700 && cpu.critical == 900)
        #expect(cpu.severities([1000, 1, 1, 1, 1], start: 0, bucket: 3600) == [0, 1, 2, 2, 0])
        #expect(cpu.counts([1, nil, 1, 1], start: 0, bucket: 3600) == (0, 2))
        rules.systemCPU.enabled = false
        #expect(CalendarStatus(metric: .cpu, rules: rules, device: device) == nil)
        #expect(CalendarStatus(metric: .disk, rules: rules, device: device) == nil)
        // Memory ignores the value: each bucket has the pressure it recorded (kernel level 1, 2 or 4).
        let memory = try #require(CalendarStatus(metric: .memory, rules: rules, device: device, pressure: [0: 1, 3600: 2, 7200: 4]))
        #expect(memory.warn == nil && memory.severities([90, 90, 10, 10], start: 0, bucket: 3600) == [0, 1, 2, 0])
        #expect(memory.counts([1, nil, 1], start: 0, bucket: 3600) == (0, 1))
    }

    @Test func usualIsPerWeekdayAndHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 1 Oct 2026 is a Thursday. Three weeks of hours from Thu 1 Oct 0:00: 10 on Thursdays at hour 0, 20 elsewhere.
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!.timeIntervalSince1970
        let totals: [Double?] = (0..<(21 * 24)).map { i in i % (7 * 24) == 0 ? 10 : (i < 24 ? nil : 20) }
        let usual = CalendarUsual(totals: totals, start: start, calendar: calendar)
        #expect(usual.value(from: start + 7 * 86_400, to: start + 7 * 86_400 + 3600) == 10)
        // Thursday 1 to 2 AM: no data in the first week, two later weeks.
        #expect(usual.value(from: start + 3600, to: start + 7200) == 20)
        // Friday 0 AM: data in all three weeks.
        #expect(usual.value(from: start + 86_400, to: start + 90_000) == 20)
        // One Thursday of data is too little.
        let thin = CalendarUsual(totals: Array(totals.prefix(30)), start: start, calendar: calendar)
        #expect(thin.value(from: start, to: start + 3600) == nil)
    }

    @Test func statsOfADayCountPeakAndLines() {
        let status = CalendarStatus(metric: .cpu, rules: AlertRules(), device: Device(cores: 10, memory: 100),
                                    cpu: [1000 + 20 * 3600: 95, 1000 + 9 * 3600: 80])
        let hours: [Double?] = (0..<24).map { $0 == 5 ? nil : $0 == 20 ? 900 : $0 == 9 ? 800 : 100 }
        let stats = SpanStats(hours: hours, start: 1000, status: status, calendar: utc)
        #expect(stats.peak == 900 && stats.peakAt == 1000 + 20 * 3600 && stats.warning == 1 && stats.critical == 1)
        #expect(stats.average == (21 * 100 + 900 + 800) / 23.0 && stats.units.count == 24 && stats.units[5] == nil)
    }

    @Test func aSpanOfDaysHasOneUnitPerDay() {
        let stats = SpanStats(hours: (0..<72).map { Double($0 / 24) }, start: 0, status: nil, calendar: utc)
        #expect(stats.units == [0, 1, 2] && stats.warning == 0 && stats.average == 1)
    }

    @Test func aLongDayIsOneUnit() {
        // New York from midnight 31 Oct 2026: that day has 24 hours, the next (summer time ends) has 25.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let start = ny.date(from: DateComponents(year: 2026, month: 10, day: 31))!.timeIntervalSince1970
        let hours: [Double?] = (0..<(24 + 25)).map { $0 < 24 ? 1 : 2 }
        #expect(SpanStats(hours: hours, start: start, status: nil, calendar: ny).units == [1, 2])
    }

    @Test func leaderWeighsCellsByTheirBucketsWithData() {
        let a = AppKey(key: "a", name: "a"), b = AppKey(key: "b", name: "b")
        func cell(_ value: Double, _ lines: [Double?], _ top: [CellApp]) -> CalendarCell {
            CalendarCell(start: 0, end: 1, value: value, lines: lines, bucket: 1, top: top, leaders: [])
        }
        // a is 4 of 10 for one bucket; b is 9 of 10 for three buckets: b leads with 27 of 40.
        let cells = [cell(10, [10], [CellApp(app: a, value: 4)]), cell(10, [10, 10, 10, nil], [CellApp(app: b, value: 9)])]
        let leader = CalendarPeriod.leader(of: cells)
        #expect(leader?.app == b && leader?.share == 27.0 / 40.0)
        #expect(CalendarPeriod.leader(of: []) == nil)
    }
}
