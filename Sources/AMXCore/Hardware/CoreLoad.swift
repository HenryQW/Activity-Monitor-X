import Foundation

/// Per-core CPU usage from `host_processor_info` deltas; no privilege needed.
public final class CoreLoad {
    private var previous: [SystemSampler.CoreTicks]?

    public init() {}

    /// Usage 0–100 of each logical CPU since the last call; empty on the first call.
    public func read() -> [Double] {
        let ticks = SystemSampler.coreTicks()
        defer { previous = ticks }
        guard let ticks, let previous else { return [] }
        return SystemSampler.corePercents(ticks, previous)
    }
}
