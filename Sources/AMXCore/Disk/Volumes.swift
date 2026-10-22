// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Foundation
import IOKit
import IOKit.storage

/// One visible mounted volume. Carries no Disk Arbitration UUID.
public struct VolumeInfo: Sendable, Hashable, Identifiable {
    public var id: String { mountPoint }
    public let name: String
    public let mountPoint: String
    /// The volume's BSD name ("disk3s1" for the "/" snapshot); empty for mounts not backed by a device.
    public let bsdName: String
    public let fileSystem: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    /// Space for important usage, with purgeable; nil when Foundation cannot tell.
    public let availableBytes: UInt64?
    /// APFS space used by this volume; for "/" the container size minus container free.
    public let usedBytes: UInt64?
    public let isInternal: Bool
    public let isEjectable: Bool
    public let isEncrypted: Bool
    public let role: String?
    public let container: String?
}

/// An APFS container: a pool shared by its volumes.
public struct APFSContainer: Sendable, Equatable, Identifiable {
    public struct Member: Sendable, Equatable {
        public let bsdName: String
        public let name: String
        public let role: String?
        public let isEncrypted: Bool
    }

    public var id: String { bsdName }
    public let bsdName: String
    public let sizeBytes: UInt64
    /// Nil when no mounted volume without a quota shows the pool's free space.
    public let freeBytes: UInt64?
    /// Only the first physical store (a Fusion container shows one).
    public let physicalStores: [String]
    public let volumes: [Member]
}

/// `statfs` names both the struct and the function; this names the struct.
private typealias FSStat = statfs

public enum Volumes {
    struct MountRow {
        var mountPoint: String
        var device: String
        var fsType: String
        var flags: UInt32
        var totalBytes: UInt64 = 0
        var freeBytes: UInt64 = 0
    }

    public static func read() -> (volumes: [VolumeInfo], containers: [APFSContainer]) {
        let rows = mounts()
        let containers = apfsContainers(rows)
        // Disk Utility shows the Data volume's encryption for Macintosh HD.
        let dataBSD = rows.first { $0.mountPoint == "/System/Volumes/Data" }.flatMap { bsdName($0.device) }
        var members: [String: (container: APFSContainer, member: APFSContainer.Member)] = [:]
        for c in containers { for m in c.volumes { members[m.bsdName] = (c, m) } }

        let volumes = visible(rows).map { row -> VolumeInfo in
            let bsd = bsdName(row.device).map(strippingSnapshot) ?? ""
            let owner = members[bsd]
            var total = row.totalBytes, free = row.freeBytes
            let used: UInt64?
            if row.mountPoint == "/", let c = owner?.container, let poolFree = c.freeBytes {
                // As the system shows Macintosh HD.
                total = c.sizeBytes
                free = poolFree
                used = total - free
            } else {
                used = spaceUsed(row.mountPoint)
            }
            let encryption = members[row.mountPoint == "/" ? dataBSD ?? bsd : bsd]?.member.isEncrypted
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey,
                                             .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsEncryptedKey]
            let values = try? URL(fileURLWithPath: row.mountPoint, isDirectory: true).resourceValues(forKeys: keys)
            return VolumeInfo(name: values?.volumeName ?? (row.mountPoint as NSString).lastPathComponent,
                              mountPoint: row.mountPoint, bsdName: bsd, fileSystem: row.fsType,
                              totalBytes: total, freeBytes: free,
                              // Foundation gives 0 for a volume it cannot assess.
                              availableBytes: values?.volumeAvailableCapacityForImportantUsage
                                  .flatMap { $0 > 0 ? UInt64($0) : nil },
                              usedBytes: used,
                              isInternal: values?.volumeIsInternal ?? false,
                              isEjectable: values?.volumeIsEjectable ?? false,
                              isEncrypted: encryption ?? values?.volumeIsEncrypted ?? false,
                              role: owner?.member.role, container: owner?.container.bsdName)
        }
        return (volumes, containers)
    }

    static func visible(_ rows: [MountRow]) -> [MountRow] {
        rows.filter { $0.flags & UInt32(MNT_DONTBROWSE) == 0 && !["devfs", "autofs", "nullfs"].contains($0.fsType) }
    }

    /// "disk3s5" -> "disk3"; nil for a whole disk or a snapshot.
    static func container(ofVolume bsd: String) -> String? {
        guard let parts = diskParts(bsd), parts.count == 2 else { return nil }
        return "disk\(parts[0])"
    }

    /// "disk3s1s1" (a mounted snapshot) -> "disk3s1"; anything else unchanged.
    static func strippingSnapshot(_ bsd: String) -> String {
        guard let parts = diskParts(bsd), parts.count == 3 else { return bsd }
        return "disk\(parts[0])s\(parts[1])"
    }

    /// "disk3s1s1" -> ["3", "1", "1"]; nil unless "disk" then numbers joined by "s".
    private static func diskParts(_ bsd: String) -> [Substring]? {
        guard bsd.hasPrefix("disk") else { return nil }
        let parts = bsd.dropFirst(4).split(separator: "s", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) } ? parts : nil
    }

    private static func bsdName(_ device: String) -> String? {
        device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : nil
    }

    /// `MNT_NOWAIT` so a dead network mount cannot stall the call. Free is `f_bavail`, as `df` shows.
    private static func mounts() -> [MountRow] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var buffer = [FSStat](repeating: FSStat(), count: Int(count))
        let filled = getfsstat(&buffer, Int32(MemoryLayout<FSStat>.stride * buffer.count), MNT_NOWAIT)
        return buffer.prefix(Int(max(0, filled))).map { fs in
            let block = UInt64(fs.f_bsize)
            return MountRow(mountPoint: string(fs.f_mntonname), device: string(fs.f_mntfromname),
                            fsType: string(fs.f_fstypename), flags: fs.f_flags,
                            totalBytes: fs.f_blocks * block, freeBytes: fs.f_bavail * block)
        }
    }

    /// `getattrlist(ATTR_VOL_SPACEUSED)`: a 4-byte length, then the 8-byte value unaligned at offset 4.
    private static func spaceUsed(_ mountPoint: String) -> UInt64? {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = buffer.withUnsafeMutableBytes { getattrlist(mountPoint, &attributes, $0.baseAddress, $0.count, 0) }
        guard status == 0 else { return nil }
        let value = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
        return value >= 0 ? UInt64(value) : nil
    }

    /// Each `AppleAPFSContainer` with its `AppleAPFSVolume` children. Its parent chain holds the
    /// synthesized `AppleAPFSMedia` (the container's BSD name and size), then the physical store.
    /// Free comes from a mounted member whose statfs total is the container size (no quota).
    private static func apfsContainers(_ rows: [MountRow]) -> [APFSContainer] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleAPFSContainer"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var out: [APFSContainer] = []
        var container = IOIteratorNext(iterator)
        while container != 0 {
            defer { IOObjectRelease(container); container = IOIteratorNext(iterator) }
            var media: (bsd: String, size: UInt64?)?
            var stores: [String] = []
            var entry = container
            IOObjectRetain(entry)
            while entry != 0 {
                var parent: io_registry_entry_t = 0
                let kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
                IOObjectRelease(entry)
                entry = kr == KERN_SUCCESS ? parent : 0
                guard entry != 0, IOObjectConformsTo(entry, kIOMediaClass) != 0,
                      let bsd = property(entry, "BSD Name") as? String else { continue }
                if IOObjectConformsTo(entry, "AppleAPFSMedia") != 0 {
                    if media == nil { media = (bsd, (property(entry, "Size") as? NSNumber)?.uint64Value) }
                } else {
                    stores.append(bsd)
                    IOObjectRelease(entry)
                    entry = 0
                }
            }
            guard let media, let size = media.size else { continue }
            let free = rows.first {
                $0.fsType == "apfs" && $0.totalBytes == size
                    && bsdName($0.device).flatMap { Volumes.container(ofVolume: strippingSnapshot($0)) } == media.bsd
            }?.freeBytes
            out.append(APFSContainer(bsdName: media.bsd, sizeBytes: size, freeBytes: free,
                                     physicalStores: stores, volumes: members(of: container)))
        }
        return out.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
    }

    private static func members(of container: io_registry_entry_t) -> [APFSContainer.Member] {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(container, kIOServicePlane, &children) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(children) }
        var out: [APFSContainer.Member] = []
        var child = IOIteratorNext(children)
        while child != 0 {
            if IOObjectConformsTo(child, "AppleAPFSVolume") != 0, let bsd = property(child, "BSD Name") as? String {
                out.append(.init(bsdName: bsd, name: property(child, "FullName") as? String ?? bsd,
                                 role: (property(child, "Role") as? [String])?.first,
                                 isEncrypted: property(child, "Encrypted") as? Bool == true))
            }
            IOObjectRelease(child)
            child = IOIteratorNext(children)
        }
        return out.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
    }
}
