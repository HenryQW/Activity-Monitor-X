import Testing
@testable import AMXCore

private let now = 1_792_656_000.0

@Test func windowPicksTier() throws {
    for (from, to, source, bucket) in [
        (now - 3600, now, HistorySource.raw, 30.0),
        (now - 86_400, now, .minute, 720),
        (now - 604_800, now, .minute, 5040),
        (now - 7_776_000, now, .hour, 64_800),
        (now - 172_800, now - 169_200, .minute, 60),
    ] {
        let w = try QueryWindow.resolve(from: from, to: to, now: now)
        #expect(w == QueryWindow(from: from, to: to, source: source, bucket: bucket))
    }
    #expect(throws: AgentError.invalid("from must be before to")) { try QueryWindow.resolve(from: now, to: now, now: now) }
}

@Test func timeArgs() throws {
    for (text, expected) in [("now", now), ("-90m", now - 5400), ("-24h", now - 86_400), ("-7d", now - 604_800),
                             ("1761000000", 1_761_000_000), ("2026-10-22T08:00:00Z", 1_792_656_000),
                             ("2026-10-22T16:00:00.5+08:00", 1_792_656_000.5)] {
        #expect(try TimeArg.parse(text, now: now) == expected)
    }
    #expect(throws: AgentError.invalid("bad time: yesterday")) { try TimeArg.parse("yesterday", now: now) }
    #expect(throws: AgentError.invalid("bad time: -1e400d")) { try TimeArg.parse("-1e400d", now: now) }
}

@Test func customWindowPicksSmallestCoveringRange() {
    #expect(HistoryRange.covering(from: now - 3600, to: now, now: now) == .hour)
    #expect(HistoryRange.covering(from: now - 7200, to: now, now: now) == .day)
    // Raw keeps 1 day: an older hour reads the minute tier.
    #expect(HistoryRange.covering(from: now - 90_000, to: now - 86_400, now: now) == .day)
}

@Test func zoomStepsAroundTheShownWindow() {
    #expect(HistoryRange.wider(than: 3600) == .day)
    #expect(HistoryRange.wider(than: 7_776_000) == nil)
    #expect(HistoryRange.narrower(than: 86_400) == .hour)
    #expect(HistoryRange.narrower(than: 3600) == nil)
    #expect(HistoryRange.narrower(than: 4000) == .hour)
    // Around the middle, and never past now.
    #expect(HistoryRange.hour.window(around: (now - 7200)...(now - 3600), now: now) == (now - 7200)...(now - 3600))
    #expect(HistoryRange.day.window(around: (now - 1000)...now, now: now) == (now - 86_400)...now)
}
