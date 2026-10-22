extension EventMark {
    /// 0 info, 1 warning, 2 critical; nil for kinds the event lane does not show.
    public var level: Int? {
        switch kind {
        case "pressure": severity >= 2 ? 2 : severity >= 1 ? 1 : 0
        // Thermal "fair" (1) is not yet a warning.
        case "thermal": severity >= 3 ? 2 : severity >= 2 ? 1 : 0
        // A rule hit is a warning or critical (M4-D2).
        case "alert": severity >= 2 ? 2 : 1
        default: nil
        }
    }
}

/// One event-lane marker: events closer than the gap to its first one.
public struct EventCluster: Sendable {
    /// The first event's x.
    public let x: Double
    /// In x order, info events included.
    public let events: [EventMark]
    /// The most severe event, the earliest of those; it sets the marker's shape and colour.
    public let lead: EventMark
}

public enum EventClusters {
    /// Events at x positions (points) closer than `gap` to a cluster's first event join it, so markers never overlap.
    /// Clusters of info events only are left out; info events next to a warning stay in that cluster's list.
    public static func clusters(_ events: [(x: Double, event: EventMark)], gap: Double) -> [EventCluster] {
        var groups: [[(x: Double, event: EventMark)]] = []
        for e in events.filter({ $0.event.level != nil }).sorted(by: { $0.x < $1.x }) {
            if let first = groups.last?.first, e.x - first.x < gap { groups[groups.count - 1].append(e) } else { groups.append([e]) }
        }
        return groups.compactMap { group in
            // max(by:) keeps the first of equal elements.
            let lead = group.max { $0.event.level! < $1.event.level! }!.event
            return lead.level! >= 1 ? EventCluster(x: group[0].x, events: group.map(\.event), lead: lead) : nil
        }
    }
}
