import AMXCore

// The thing a metric or a rule is about, as a system symbol: one mapping for Calendar, Alerts and Settings.

extension Metric {
    /// The system symbol for the metric: the thing it measures.
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .energy: "bolt"
        case .gpu: "square.stack.3d.up"
        case .score: "gauge.with.dots.needle.50percent"
        }
    }
}

extension RuleName {
    /// The rules about the Mac, not an app: their subject is the part's symbol, also when the message names an app.
    static let system: Set<String> = [pressure, thermal, systemCPU, swap, freeSpace]

    /// What a rule watches, in a list's icon column (Alerts, Settings): the metric's symbol, or the part's.
    static func symbol(_ rule: String?) -> String {
        switch rule {
        case sustainedCPU, systemCPU: Metric.cpu.symbol
        case memoryGrowth, memoryJump, pressure: Metric.memory.symbol
        case diskWrites, freeSpace: Metric.disk.symbol
        case network: Metric.network.symbol
        case energy: Metric.energy.symbol
        case gpu: Metric.gpu.symbol
        case thermal: "thermometer.medium"
        case swap: "arrow.left.arrow.right"
        default: "exclamationmark.triangle"
        }
    }
}
