import Testing
@testable import AMXCore

@Suite struct EventFocusTests {
    private let now = 1_792_656_000.0

    @Test func focusPicksSmallestRange() {
        var w = EventFocus.window(for: now - 600, lookback: 600, now: now)
        #expect(w.range == .hour && w.span == (now - 1200)...(now - 300))
        w = EventFocus.window(for: now - 1800, lookback: 1800, now: now)
        #expect(w.range == .hour && w.span == (now - 3600)...(now - 1500))
        #expect(EventFocus.window(for: now - 3000, lookback: 1800, now: now).range == .day)
        #expect(EventFocus.window(for: now - 3 * 86_400, lookback: 600, now: now).range == .week)
        w = EventFocus.window(for: now - 100 * 86_400, lookback: 600, now: now)
        #expect(w.range == .quarter && w.span == nil)
    }

    @Test func lookbackPerRule() {
        let rules = AlertRules()
        #expect(rules.lookback(rule: "sustained_cpu") == 300)
        #expect(rules.lookback(rule: "memory_growth") == 1800)
        #expect(rules.lookback(rule: "memory_jump") == 50)
        #expect(rules.lookback(rule: "pressure") == 600)
        #expect(rules.lookback(rule: "thermal") == 300)
        #expect(rules.lookback(rule: "other") == 600)
    }
}
