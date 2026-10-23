import Darwin

/// Figures the app reads itself, with no helper and no history: the Apps footer's values "now".
public enum HostReader {
    /// Ticks of all cores since boot, by state; nice counts as user. 32-bit counters that wrap.
    public struct CPUTicks: Sendable, Equatable {
        public var user: UInt32
        public var system: UInt32
        public var idle: UInt32
    }

    /// Shares of the ticks between two reads, 0 to 100 each.
    public struct CPUSplit: Sendable, Equatable {
        public let user: Double
        public let system: Double
        public let idle: Double

        /// Nil when no tick passed. Wrapping subtraction gives the small true delta across a counter wrap.
        public init?(_ now: CPUTicks, since before: CPUTicks) {
            let user = Double(now.user &- before.user), system = Double(now.system &- before.system)
            let idle = Double(now.idle &- before.idle), total = user + system + idle
            guard total > 0 else { return nil }
            (self.user, self.system, self.idle) = (user / total * 100, system / total * 100, idle / total * 100)
        }
    }

    /// The memory breakdown as the stock app names it: used is app memory, wired and compressed.
    public struct Memory: Sendable, Equatable {
        public let app: UInt64
        public let wired: UInt64
        public let compressed: UInt64
        public let cached: UInt64
        public var used: UInt64 { app + wired + compressed }
    }

    public static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: t.0 &+ t.3, system: t.1, idle: t.2)
    }

    /// The 1, 5 and 15 min load averages.
    public static func loadAverage() -> [Double]? {
        var loads = [0.0, 0, 0]
        return getloadavg(&loads, 3) == 3 ? loads : nil
    }

    public static func memory() -> Memory? {
        guard let vm = SystemSampler.vmStatistics() else { return nil }
        func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * SystemSampler.pageSize }
        return Memory(app: CPUMath.delta(bytes(vm.internal_page_count), bytes(vm.purgeable_count)),
                      wired: bytes(vm.wire_count), compressed: bytes(vm.compressor_page_count),
                      cached: bytes(vm.external_page_count) + bytes(vm.purgeable_count))
    }
}
