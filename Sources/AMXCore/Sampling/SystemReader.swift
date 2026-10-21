// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Darwin
import Foundation

/// Whole-machine figures for one tick. Rates are per second; `cpu` is 0–100 for the machine.
public struct SystemSample: Sendable {
    public var cpu = 0.0
    public var pressurePct = 0.0
    public var load1 = 0.0
    public var diskR = 0.0
    public var diskW = 0.0
    public var diskIOPS = 0.0
    public var diskLatMs = 0.0
    public var diskUtil = 0.0
    public var gpu = 0.0
    public var memUsed: UInt64 = 0
    public var memCompressed: UInt64 = 0
    public var swapUsed: UInt64 = 0
    public var pressureLevel = 1
    public var thermalState = 0
    public var tempCPU: Double?
    public var tempGPU: Double?
    public var tempSSD: Double?
    public var netIn = 0.0
    public var netOut = 0.0

    public init() {}
}

/// Turns system counters into one `SystemSample` per tick. The first call has no
/// previous counters, so its CPU and disk rates are 0.
public final class SystemSampler {
    /// Live sends only CPU, memory used, pressure level and thermal state, so it skips swap, disks, GPU and SMC.
    public init(liveOnly: Bool = false) { self.liveOnly = liveOnly }

    private let liveOnly: Bool

    private let disks = DiskStatsReader()
    private let smc = SMCReader()
    private var previousNow: Double?
    private var previousTicks: [CoreTicks]?
    private var previousDisks: [UInt64: DiskCounters] = [:]
    private var previousLoad: UInt64?

    public func sample(now: Double) -> SystemSample {
        let wall = previousNow.map { now - $0 } ?? 0
        let valid = wall > 0 && wall <= 60
        var s = SystemSample()

        let ticks = Self.coreTicks()
        if let previousTicks, let ticks { s.cpu = Self.cpuPercent(ticks, previousTicks) }
        previousTicks = ticks
        var loads = [0.0, 0, 0]
        if getloadavg(&loads, 3) == 3 { s.load1 = loads[0] }
        s.thermalState = ProcessInfo.processInfo.thermalState.rawValue

        if let vm = Self.vmStatistics() {
            let page = Self.pageSize
            func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * page }
            let anonymous = CPUMath.delta(bytes(vm.internal_page_count), bytes(vm.purgeable_count))
            s.memCompressed = bytes(vm.compressor_page_count)
            s.memUsed = anonymous + bytes(vm.wire_count) + s.memCompressed
        }
        var level: Int32 = 0
        if Self.sysctl("kern.memorystatus_vm_pressure_level", into: &level), [1, 2, 4].contains(level) {
            s.pressureLevel = Int(level)
        }
        guard !liveOnly else { previousNow = now; return s }
        var swap = xsw_usage()
        if Self.sysctl("vm.swapusage", into: &swap) { s.swapUsed = swap.xsu_used }
        let load = s.memCompressed &+ s.swapUsed
        let growth = valid ? previousLoad.map { Double(CPUMath.delta(load, $0)) / wall } ?? 0 : 0
        previousLoad = load
        s.pressurePct = PressureIndex.percent(level: s.pressureLevel, compressed: s.memCompressed,
                                              swap: s.swapUsed, ram: Self.ram, growthBytesPerSec: growth)

        let disk = disks.read()
        if valid { addDiskRates(to: &s, current: disk, wall: wall) }
        previousDisks = disk

        s.gpu = GPUReader.deviceUtilization()
        let temps = smc.read(now: now)
        s.tempCPU = temps.cpu
        s.tempGPU = temps.gpu
        s.tempSSD = temps.ssd
        previousNow = now
        return s
    }

    /// Sums the disks seen on both ticks; a newly attached disk starts at zero.
    private func addDiskRates(to s: inout SystemSample, current: [UInt64: DiskCounters], wall: Double) {
        var ops: UInt64 = 0, nanos: UInt64 = 0
        for (id, cur) in current {
            guard let prev = previousDisks[id] else { continue }
            let d = { (k: KeyPath<DiskCounters, UInt64>) in CPUMath.delta(cur[keyPath: k], prev[keyPath: k]) }
            s.diskR += Double(d(\.readBytes)) / wall
            s.diskW += Double(d(\.writeBytes)) / wall
            ops += d(\.reads) + d(\.writes)
            let busy = d(\.readNanos) + d(\.writeNanos)
            nanos += busy
            s.diskUtil = max(s.diskUtil, min(100, Double(busy) / (wall * 1e9) * 100))
        }
        s.diskIOPS = Double(ops) / wall
        s.diskLatMs = DiskMath.latencyMs(timeDeltaNanos: nanos, opsDelta: ops)
    }

    // MARK: - CPU

    struct CoreTicks {
        var busy: UInt32
        var idle: UInt32
    }

    /// Busy share of all cores' ticks, 0–100. UInt32 ticks use wrapping subtraction so a
    /// counter wrap yields the small true delta rather than a spurious idle of 0.
    static func cpuPercent(_ current: [CoreTicks], _ previous: [CoreTicks]) -> Double {
        guard current.count == previous.count else { return 0 }
        var busy = 0.0, total = 0.0
        for (c, p) in zip(current, previous) {
            let b = Double(c.busy &- p.busy)
            busy += b
            total += b + Double(c.idle &- p.idle)
        }
        return total > 0 ? min(busy / total * 100, 100) : 0
    }

    /// Per-core ticks from `host_processor_info`; nice is folded into user.
    private static func coreTicks() -> [CoreTicks]? {
        var cpuCount = natural_t(0)
        var info: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
                == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(cpuCount)).map { i in
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[i * Int(CPU_STATE_MAX) + Int(state)]) }
            return CoreTicks(busy: tick(CPU_STATE_USER) &+ tick(CPU_STATE_NICE) &+ tick(CPU_STATE_SYSTEM),
                             idle: tick(CPU_STATE_IDLE))
        }
    }

    // MARK: - Memory

    private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        return host_page_size(mach_host_self(), &size) == KERN_SUCCESS && size > 0
            ? UInt64(size) : UInt64(getpagesize())
    }()

    private static let ram: UInt64 = {
        var v: UInt64 = 0
        return sysctl("hw.memsize", into: &v) ? v : 0
    }()

    private static func vmStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? stats : nil
    }

    private static func sysctl<T>(_ name: String, into value: inout T) -> Bool {
        var size = MemoryLayout<T>.size
        return withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) } == 0
    }
}
