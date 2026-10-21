// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import DiskArbitration
import Foundation
import IOKit
import IOKit.storage

enum DiskMath {
    /// Average service time per operation; 0 when no operation completed.
    static func latencyMs(timeDeltaNanos: UInt64, opsDelta: UInt64) -> Double {
        opsDelta > 0 ? Double(timeDeltaNanos) / Double(opsDelta) / 1_000_000 : 0
    }
}

/// Cumulative counters of one block storage driver since attach.
struct DiskCounters {
    var readBytes: UInt64
    var writeBytes: UInt64
    var reads: UInt64
    var writes: UInt64
    var readNanos: UInt64
    var writeNanos: UInt64
}

/// Reads `IOBlockStorageDriver` statistics for each physical whole disk.
/// Disk images and other virtual disks are excluded via Disk Arbitration.
final class DiskStatsReader {
    private let session = DASessionCreate(kCFAllocatorDefault)
    private var isVirtual: [UInt64: Bool] = [:]

    /// Counters keyed by the driver's registry entry id.
    func read() -> [UInt64: DiskCounters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass),
                                           &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var out: [UInt64: DiskCounters] = [:]
        var driver = IOIteratorNext(iterator)
        while driver != 0 {
            defer { IOObjectRelease(driver); driver = IOIteratorNext(iterator) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS,
                  let bsdName = Self.wholeMediaBSDName(of: driver),
                  let stats = Self.property(driver, kIOBlockStorageDriverStatisticsKey) as? [String: Any]
            else { continue }
            if isVirtual[id] == nil { isVirtual[id] = virtual(bsdName: bsdName) }
            guard isVirtual[id] == false else { continue }
            func n(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
            out[id] = DiskCounters(readBytes: n(kIOBlockStorageDriverStatisticsBytesReadKey),
                                   writeBytes: n(kIOBlockStorageDriverStatisticsBytesWrittenKey),
                                   reads: n(kIOBlockStorageDriverStatisticsReadsKey),
                                   writes: n(kIOBlockStorageDriverStatisticsWritesKey),
                                   readNanos: n(kIOBlockStorageDriverStatisticsTotalReadTimeKey),
                                   writeNanos: n(kIOBlockStorageDriverStatisticsTotalWriteTimeKey))
        }
        return out
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

    private func virtual(bsdName: String) -> Bool {
        guard let session, let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName),
              let d = DADiskCopyDescription(disk) as? [String: Any] else { return false }
        let model = d[kDADiskDescriptionDeviceModelKey as String] as? String
        let proto = d[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let path = d[kDADiskDescriptionDevicePathKey as String] as? String ?? ""
        return model == "Disk Image" || proto == "Virtual Interface" || path.contains("IOHDIXController")
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
