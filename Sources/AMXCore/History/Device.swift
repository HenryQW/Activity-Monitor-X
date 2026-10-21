import Foundation

/// This Mac's size, which turns CPU and memory into a share of the machine.
public struct Device: Sendable, Equatable {
    public let cores: Int
    public let memory: Double

    public init(cores: Int, memory: Double) {
        self.cores = cores
        self.memory = memory
    }

    public static let current = Device(cores: ProcessInfo.processInfo.activeProcessorCount,
                                       memory: Double(ProcessInfo.processInfo.physicalMemory))

    /// Score in percent of this Mac: half CPU share of all cores, half memory share of RAM. `cpu` is in percent of
    /// one core, `mem` in bytes. Linear, so member scores add up. `HistoryReader` repeats the formula in SQL.
    public func score(cpu: Double, mem: Double) -> Double { 0.5 * cpu / Double(cores) + 50 * mem / memory }
}
