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
