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
        // A Calendar hour that is still running ends at now.
        w = EventFocus.window(from: now - 1800, to: now + 1800, now: now)
        #expect(w.range == .hour && w.span == (now - 1800)...now)
    }

    @Test func onlyFreshNewRowsNotify() {
        let rows = [(1, now - 30), (2, now - 600), (3, now - 599), (4, now)].map {
            EventMark(id: $0.0, ts: $0.1, kind: "alert", severity: 1, message: "", app: nil, rule: "sustained_cpu")
        }
        #expect(EventMark.toNotify(rows, after: 1, now: now).map(\.id) == [3, 4])
        #expect(EventMark.toNotify(rows, after: 4, now: now).isEmpty)
    }
}
