import Foundation
import Testing
@testable import AMXCore

private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private let day = 86_400.0, hour = 3600.0

private func track(_ id: Int64, _ app: String, _ slices: [(Double, Double, Double)], start: Double = 0,
                   lastSeen: Double = 0) -> ProcessTrack {
    ProcessTrack(processID: id, pid: Int32(id), startTime: start, name: app, app: AppKey(key: app, name: app),
                 lastSeen: lastSeen, slices: slices.map { Slice(start: $0.0, end: $0.1, value: $0.2) })
}

private func rank(_ app: String, _ average: Double) -> AppRank {
    AppRank(app: AppKey(key: app, name: app), average: average, peak: average, processes: [])
}

@Test func usualNeedsTwoDays() {
    #expect(UsualProfile([], calendar: utc).usual(of: AppKey(key: "A", name: "A"), from: 0, to: hour) == nil)
    let short = UsualProfile([track(1, "A", [(0, 1.5 * day, 1)])], calendar: utc)
    #expect(short.usual(of: AppKey(key: "A", name: "A"), from: 0, to: hour) == nil)
}

@Test func usualAtSameHoursOfDay() {
    // B marks 3 days recorded; A runs at 9:00 to 10:00 each day; C is absent.
    let a = track(1, "A", (0..<3).map { (Double($0) * day + 9 * hour, Double($0) * day + 10 * hour, 10) })
    let profile = UsualProfile([a, track(2, "B", [(0, 3 * day, 1)])], calendar: utc)
    let key = { AppKey(key: $0, name: $0) }
    #expect(profile.usual(of: key("A"), from: 3 * day + 9 * hour, to: 3 * day + 10 * hour) == 10)
    #expect(profile.usual(of: key("A"), from: 3 * day + 10 * hour, to: 3 * day + 11 * hour) == 0)
    #expect(profile.usual(of: key("A"), from: 3 * day + 9 * hour, to: 3 * day + 11 * hour) == 5)
    #expect(profile.usual(of: key("C"), from: 0, to: hour) == 0)
}

@Test func usualWeighsPartialDays() {
    // 2.5 days: hour 1 is recorded on 3 days, and A ran in it on one of them.
    let profile = UsualProfile([track(1, "A", [(hour, 2 * hour, 6)]), track(2, "B", [(0, 2.5 * day, 1)])], calendar: utc)
    #expect(profile.usual(of: AppKey(key: "A", name: "A"), from: 3 * day + hour, to: 3 * day + 2 * hour) == 2)
}

@Test func describeAgainstUsual() {
    let en = Locale(identifier: "en_US")
    #expect(UsualProfile.describe(11, usual: 10, locale: en) == "About usual")
    #expect(UsualProfile.describe(24, usual: 10, locale: en) == "2.4× usual")
    #expect(UsualProfile.describe(5, usual: 0, locale: en) == "Usually idle at these hours")
}

@Test func biggestChangesCountAbsentAppsAsZero() {
    let (up, down) = AppChange.biggest([rank("A", 10), rank("B", 5), rank("D", 3)], previous: [rank("A", 2), rank("C", 4), rank("D", 3)])
    #expect(up.map(\.app.key) == ["A", "B"])
    #expect(up.map(\.delta) == [8, 5])
    #expect(down.map(\.app.key) == ["C"])
    #expect(down.map(\.delta) == [-4])
}

@Test func launchesInWindowNewestFirst() {
    let tracks = [
        track(1, "before", [(0, 100, 1)], start: -50, lastSeen: 100),  // started before, quit at 100
        track(2, "alive", [(20, 200, 1)], start: 20, lastSeen: 1000),  // started at 20, alive at the end
        track(3, "past", [(30, 200, 1)], start: 30, lastSeen: 150),  // gone, but its last slice reaches the end
    ]
    let events = LaunchEvent.list(tracks, from: 0, to: 200, exitedBefore: 500)
    #expect(events.map(\.name) == ["before", "past", "alive"])
    #expect(events.map(\.isQuit) == [true, false, false])
    #expect(events.map(\.ts) == [100, 30, 20])
}
