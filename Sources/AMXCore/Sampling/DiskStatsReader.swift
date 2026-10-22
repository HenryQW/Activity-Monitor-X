// MIT License. See Packaging/Credits.html.
import DiskArbitration
import Foundation
import IOKit
import IOKit.storage

/// One disk's rates over an interval; bytes and operations per second, latency per operation, utilisation 0–100.
public struct DiskRate: Sendable, Equatable {
    public let readBps, writeBps, iops, latencyMs, utilPct: Double
}

public enum DiskMath {
    /// Average service time per operation; 0 when no operation completed.
    static func latencyMs(timeDeltaNanos: UInt64, opsDelta: UInt64) -> Double {
        opsDelta > 0 ? Double(timeDeltaNanos) / Double(opsDelta) / 1_000_000 : 0
    }

    /// Rates by BSD name of the disks seen on both reads; a newly attached disk starts at zero.
    public static func rates(current: [UInt64: DiskCounters], previous: [UInt64: DiskCounters],
                             wall: Double) -> [String: DiskRate] {
        var out: [String: DiskRate] = [:]
        for (id, cur) in current {
            guard let prev = previous[id] else { continue }
            let d = { (k: KeyPath<DiskCounters, UInt64>) in CPUMath.delta(cur[keyPath: k], prev[keyPath: k]) }
            let ops = d(\.reads) + d(\.writes)
            let busy = d(\.readNanos) + d(\.writeNanos)
            out[cur.bsdName] = DiskRate(readBps: Double(d(\.readBytes)) / wall, writeBps: Double(d(\.writeBytes)) / wall,
                                        iops: Double(ops) / wall, latencyMs: latencyMs(timeDeltaNanos: busy, opsDelta: ops),
                                        utilPct: min(100, Double(busy) / (wall * 1e9) * 100))
        }
        return out
    }

    /// Bytes and operations summed, latency weighted by operations, utilisation the busiest disk's.
    public static func total(_ rates: [DiskRate]) -> DiskRate {
        let iops = rates.reduce(0) { $0 + $1.iops }
        return DiskRate(readBps: rates.reduce(0) { $0 + $1.readBps }, writeBps: rates.reduce(0) { $0 + $1.writeBps },
                        iops: iops,
                        latencyMs: iops > 0 ? rates.reduce(0) { $0 + $1.latencyMs * $1.iops } / iops : 0,
                        utilPct: rates.map(\.utilPct).max() ?? 0)
    }
}

/// Cumulative counters of one block storage driver since attach.
public struct DiskCounters: Sendable {
    public var bsdName: String
    public var readBytes: UInt64
    public var writeBytes: UInt64
    public var reads: UInt64
    public var writes: UInt64
    public var readNanos: UInt64
    public var writeNanos: UInt64
}

/// A physical whole disk, as Disk Arbitration describes it.
public struct PhysicalDisk: Sendable, Equatable, Identifiable {
    public let bsdName: String
    public let model: String?
    public let protocolName: String?
    public let isInternal: Bool
    public let sizeBytes: UInt64
    public var id: String { bsdName }
}

/// Reads `IOBlockStorageDriver` statistics for each physical whole disk.
/// Disk images and other virtual disks are excluded via Disk Arbitration.
public final class DiskStatsReader {
    public init() {}

    private let session = DASessionCreate(kCFAllocatorDefault)
    private var isVirtual: [UInt64: Bool] = [:]

    /// Counters keyed by the driver's registry entry id.
    public func read() -> [UInt64: DiskCounters] {
        var out: [UInt64: DiskCounters] = [:]
        forEachPhysicalDriver { driver, id, bsdName in
            guard let stats = Self.property(driver, kIOBlockStorageDriverStatisticsKey) as? [String: Any] else { return }
            func n(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
            out[id] = DiskCounters(bsdName: bsdName, readBytes: n(kIOBlockStorageDriverStatisticsBytesReadKey),
                                   writeBytes: n(kIOBlockStorageDriverStatisticsBytesWrittenKey),
                                   reads: n(kIOBlockStorageDriverStatisticsReadsKey),
                                   writes: n(kIOBlockStorageDriverStatisticsWritesKey),
                                   readNanos: n(kIOBlockStorageDriverStatisticsTotalReadTimeKey),
                                   writeNanos: n(kIOBlockStorageDriverStatisticsTotalWriteTimeKey))
        }
        return out
    }

    /// The physical whole disks, by the same walk and virtual filter as `read()`.
    public func devices() -> [PhysicalDisk] {
        var out: [PhysicalDisk] = []
        forEachPhysicalDriver { _, _, bsdName in
            let d = description(bsdName: bsdName)
            out.append(PhysicalDisk(
                bsdName: bsdName,
                model: (d?[kDADiskDescriptionDeviceModelKey as String] as? String)?.trimmingCharacters(in: .whitespaces),
                protocolName: d?[kDADiskDescriptionDeviceProtocolKey as String] as? String,
                isInternal: d?[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false,
                sizeBytes: (d?[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0))
        }
        return out
    }

    /// Calls `body` for each block storage driver whose whole-disk media is not virtual.
    private func forEachPhysicalDriver(_ body: (io_registry_entry_t, UInt64, String) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var driver = IOIteratorNext(iterator)
        while driver != 0 {
            defer { IOObjectRelease(driver); driver = IOIteratorNext(iterator) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS,
                  let bsdName = Self.wholeMediaBSDName(of: driver) else { continue }
            if isVirtual[id] == nil { isVirtual[id] = virtual(bsdName: bsdName) }
            guard isVirtual[id] == false else { continue }
            body(driver, id, bsdName)
        }
    }

    /// BSD name of the driver's immediate whole-disk media child, if any.
    private static func wholeMediaBSDName(of driver: io_registry_entry_t) -> String? {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(driver, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        var child = IOIteratorNext(children)
        while child != 0 {
            let whole = IOObjectConformsTo(child, kIOMediaClass) != 0 && property(child, "Whole") as? Bool == true
            let name = whole ? property(child, "BSD Name") as? String : nil
            IOObjectRelease(child)
            if whole { return name }
            child = IOIteratorNext(children)
        }
        return nil
    }

    private func description(bsdName: String) -> [String: Any]? {
        guard let session, let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else { return nil }
        return DADiskCopyDescription(disk) as? [String: Any]
    }

    private func virtual(bsdName: String) -> Bool {
        guard let d = description(bsdName: bsdName) else { return false }
        let model = d[kDADiskDescriptionDeviceModelKey as String] as? String
        let proto = d[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let path = d[kDADiskDescriptionDevicePathKey as String] as? String ?? ""
        return model == "Disk Image" || proto == "Virtual Interface" || path.contains("IOHDIXController")
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
