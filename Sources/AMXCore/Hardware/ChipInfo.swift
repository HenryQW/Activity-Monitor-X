import Foundation

public struct ChipInfo: Sendable, Equatable {
    public struct Cluster: Sendable, Equatable {
        public let name: String
        public let cores: Int
    }

    public let name: String
    public let model: String
    public let clusters: [Cluster]
    public let memory: UInt64

    /// Cluster names come from the kernel ("Super", "Performance"); they are never assumed to be P and E.
    public static func current() -> ChipInfo {
        let levels: Int32 = number("hw.nperflevels")
        return ChipInfo(
            name: string("machdep.cpu.brand_string"), model: string("hw.model"),
            clusters: (0..<levels).map {
                Cluster(name: string("hw.perflevel\($0).name"), cores: Int(number("hw.perflevel\($0).physicalcpu") as Int32))
            },
            memory: number("hw.memsize"))
    }

    /// The logical CPU indexes of cluster `index`. The kernel numbers `hw.perflevelN` from the fastest level, but
    /// `host_processor_info` lists the slowest level first: on this Mac the IORegistry `cpu` nodes show logical-cpu-id
    /// 0-9 with cluster-type "M" (the 10 Performance cores, perflevel1) and 10-14 with "P" (the 5 Super cores,
    /// perflevel0). So the last cluster takes the first indexes.
    public func cpuIndexes(cluster index: Int) -> Range<Int> {
        let start = clusters[(index + 1)...].reduce(0) { $0 + $1.cores }
        return start..<(start + clusters[index].cores)
    }

    private static func number<T: FixedWidthInteger>(_ name: String) -> T {
        var v: T = 0
        var size = MemoryLayout<T>.size
        sysctlbyname(name, &v, &size, nil, 0)
        return v
    }

    private static func string(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
    }
}
