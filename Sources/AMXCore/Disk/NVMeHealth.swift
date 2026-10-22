// MIT License. See Packaging/Credits.html.
import CAMX

/// The NVMe SMART / Health log of one disk. The C shim fetches the raw
/// 512 bytes; everything here is parsing.
public struct NVMeHealth: Sendable, Equatable {
    public let criticalWarning: UInt8
    public let temperatureCelsius: Double?
    public let availableSpare: Int
    public let spareThreshold: Int
    public let percentageUsed: Int
    public let dataReadBytes: UInt64
    public let dataWrittenBytes: UInt64
    public let powerCycles: UInt64
    public let powerOnHours: UInt64
    public let unsafeShutdowns: UInt64
    public let mediaErrors: UInt64

    public var isHealthy: Bool { criticalWarning == 0 && availableSpare >= spareThreshold }

    /// Decodes the log page (NVMe spec layout, little-endian, 128-bit counters
    /// truncated to their low 64 bits). Nil for input shorter than 512 bytes.
    public static func parse(_ log: [UInt8]) -> NVMeHealth? {
        guard log.count >= 512 else { return nil }
        func u64(_ offset: Int) -> UInt64 {
            (0..<8).reduce(0) { $0 | UInt64(log[offset + $1]) << (8 * $1) }
        }
        let kelvin = UInt16(log[1]) | UInt16(log[2]) << 8
        // One data unit is 1,000 blocks of 512 bytes.
        return NVMeHealth(criticalWarning: log[0],
                          temperatureCelsius: kelvin == 0 ? nil : Double(kelvin) - 273.15,
                          availableSpare: Int(log[3]), spareThreshold: Int(log[4]), percentageUsed: Int(log[5]),
                          dataReadBytes: u64(32) &* 512_000, dataWrittenBytes: u64(48) &* 512_000,
                          powerCycles: u64(112), powerOnHours: u64(128),
                          unsafeShutdowns: u64(144), mediaErrors: u64(160))
    }

    /// Nil when the disk has no SMART log (external, USB) or the read fails.
    public static func read(bsdName: String) -> NVMeHealth? {
        var log = [UInt8](repeating: 0, count: 512)
        guard camx_nvme_smart_read(bsdName, &log) == 0 else { return nil }
        return parse(log)
    }
}
