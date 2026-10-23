import Foundation

/// One app's share of the energy impact right now; a nil app is Other.
public struct EnergyShare: Equatable, Sendable {
    public let app: AppKey?
    public let share: Double

    public init(app: AppKey?, share: Double) { (self.app, self.share) = (app, share) }

    /// The top `count` apps by summed energy impact and the running `kept` apps (by key), then Other for the rest; empty
    /// when the total is 0. Apps come largest first, or by name with `byName`.
    /// A query keeps only the apps it matches (`AppSearch`); the others go into Other.
    public static func top(_ processes: [LiveProcess], count: Int = 5, query: String = "", kept: Set<String> = [],
                           byName: Bool = false) -> [EnergyShare] {
        var sums: [AppKey: Double] = [:]
        for p in processes where p.energy > 0 || kept.contains(p.appKey) {
            sums[AppKey(key: p.appKey, name: p.appName), default: 0] += max(0, p.energy)
        }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        var shown = sums.sorted { ($0.value, $1.key.key) > ($1.value, $0.key.key) }
            .filter { query.isEmpty || AppSearch.matches($0.key, query) }
            .enumerated().filter { $0.offset < count && $0.element.value > 0 || kept.contains($0.element.key.key) }.map(\.element)
        if byName { shown.sort { $0.key.name.localizedStandardCompare($1.key.name) == .orderedAscending } }
        let rest = total - shown.reduce(0) { $0 + $1.value }
        return shown.map { EnergyShare(app: $0.key, share: $0.value / total) }
            + (rest > 0 ? [EnergyShare(app: nil, share: rest / total)] : [])
    }
}

public enum EnergyNode: Hashable, Sendable {
    case adapter, battery, mac, app(AppKey), other
    /// A process of the expanded app, and the rest of its processes.
    case process(pid: Int32, startTime: Double, name: String), otherProcesses
}
/// The energy diagram in three columns: sources, the Mac (with the battery while it charges), apps. Link weights are
/// watts; while the Mac's watts are unknown they are shares of 1, the providing source carries all, and `watts` is nil.
/// With `expanded`, a fourth column splits that app's band into its top `count` processes and Other, each by its share
/// of the app's energy impact.
public struct EnergyFlows: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        public let from: EnergyNode
        public let to: EnergyNode
        public let weight: Double
        public let watts: Double?
    }

    public let columns: [[EnergyNode]]
    public let links: [Link]

    public init(_ power: PowerReading, shares: [EnergyShare], expanded: AppKey? = nil, processes: [LiveProcess] = [],
                count: Int = 5) {
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
        var columns = [sources, middle, shares.map { $0.app.map(EnergyNode.app) ?? .other }]
        if let expanded, let band = links.first(where: { $0.to == .app(expanded) }) {
            let own = processes.filter { $0.appKey == expanded.key && $0.energy > 0 }.sorted { ($0.energy, $1.pid) > ($1.energy, $0.pid) }
            let total = own.reduce(0) { $0 + $1.energy }, top = own.prefix(count)
            let rest = total - top.reduce(0) { $0 + $1.energy }
            let parts = top.map { (EnergyNode.process(pid: $0.pid, startTime: $0.startTime, name: $0.name), $0.energy / total) }
                + (rest > 0 ? [(EnergyNode.otherProcesses, rest / total)] : [])
            links += parts.map { node, share in
                Link(from: band.to, to: node, weight: band.weight * share, watts: band.watts.map { $0 * share })
            }
            if !parts.isEmpty { columns.append(parts.map(\.0)) }
        }
        self.columns = columns
        self.links = links
    }
}
