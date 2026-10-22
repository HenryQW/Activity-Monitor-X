/// One app's share of the energy impact right now; a nil app is Other.
public struct EnergyShare: Equatable, Sendable {
    public let app: AppKey?
    public let share: Double

    public init(app: AppKey?, share: Double) { (self.app, self.share) = (app, share) }

    /// The top `count` apps by summed energy impact, largest first, then Other for the rest; empty when the total is 0.
    public static func top(_ processes: [LiveProcess], count: Int = 5) -> [EnergyShare] {
        var sums: [AppKey: Double] = [:]
        for p in processes where p.energy > 0 { sums[AppKey(key: p.appKey, name: p.appName), default: 0] += p.energy }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        let top = sums.sorted { ($0.value, $1.key.key) > ($1.value, $0.key.key) }.prefix(count)
        let rest = total - top.reduce(0) { $0 + $1.value }
        return top.map { EnergyShare(app: $0.key, share: $0.value / total) }
            + (rest > 0 ? [EnergyShare(app: nil, share: rest / total)] : [])
    }
}

public enum EnergyNode: Hashable, Sendable {
    case adapter, battery, mac, app(AppKey), other
}

/// The energy diagram in three columns: sources, the Mac (with the battery while it charges), apps. Link weights are
/// watts; while the Mac's watts are unknown they are shares of 1, the providing source carries all, and `watts` is nil.
public struct EnergyFlows: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        public let from: EnergyNode
        public let to: EnergyNode
        public let weight: Double
        public let watts: Double?
    }

    public let columns: [[EnergyNode]]
    public let links: [Link]

    public init(_ power: PowerReading, shares: [EnergyShare]) {
        var sources: [EnergyNode] = [], middle: [EnergyNode] = [.mac], links: [Link] = []
        let system = power.systemWatts
        if let system {
            let watts = power.battery?.watts ?? 0
            let (charge, discharge) = (max(0, watts), max(0, -watts))
            if power.adapterConnected {
                sources.append(.adapter)
                links.append(Link(from: .adapter, to: .mac, weight: system - discharge, watts: system - discharge))
                if charge > 0 {
                    middle.append(.battery)
                    links.append(Link(from: .adapter, to: .battery, weight: charge, watts: charge))
                }
            }
            if power.battery != nil, !middle.contains(.battery) {
                sources.append(.battery)
                links.append(Link(from: .battery, to: .mac, weight: discharge, watts: discharge))
            }
        } else {
            let source: EnergyNode = power.adapterConnected || power.battery == nil ? .adapter : .battery
            sources = [source] + (source == .adapter && power.battery != nil ? [.battery] : [])
            links.append(Link(from: source, to: .mac, weight: 1, watts: nil))
        }
        let total = system ?? 1
        for share in shares {
            let node = share.app.map(EnergyNode.app) ?? .other
            links.append(Link(from: .mac, to: node, weight: share.share * total, watts: system.map { share.share * $0 }))
        }
        columns = [sources, middle, shares.map { $0.app.map(EnergyNode.app) ?? .other }]
        self.links = links
    }
}
