import Foundation
import Testing
@testable import AMXCore

private func event(_ kind: String, _ severity: Int, _ message: String) -> EventMark {
    EventMark(id: 0, ts: 0, kind: kind, severity: severity, message: message, app: nil, rule: nil)
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

@Test func byteLabelsNeverSpellOutZero() {
    #expect(Metric.bytes(0) == "0 bytes")
    #expect(Metric.bytes(1_500_000) == "1.5 MB")
    #expect(Metric.int64(.nan) == 0)
    #expect(Metric.int64(.infinity) > .max - 1024 && Metric.int64(-1e30) == .min)
    #expect(Metric.int64(2.5) == 3)
}
