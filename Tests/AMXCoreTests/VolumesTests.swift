@testable import AMXCore
import Foundation
import Testing

@Suite struct VolumesTests {
    @Test func visibleSkipsHiddenAndPseudo() {
        let rows = [
            Volumes.MountRow(mountPoint: "/", device: "/dev/disk3s1s1", fsType: "apfs", flags: 0),
            Volumes.MountRow(mountPoint: "/System/Volumes/Data", device: "/dev/disk3s5", fsType: "apfs",
                             flags: UInt32(MNT_DONTBROWSE)),
            Volumes.MountRow(mountPoint: "/dev", device: "devfs", fsType: "devfs", flags: 0),
            Volumes.MountRow(mountPoint: "/Volumes/USB", device: "/dev/disk6s1", fsType: "msdos", flags: 0),
        ]
        #expect(Volumes.visible(rows).map(\.mountPoint) == ["/", "/Volumes/USB"])
    }

    @Test func bytesSaturate() {
        #expect(Volumes.bytes(3, 4096) == 12288)
        #expect(Volumes.bytes(.max / 2, 4096) == .max)
    }

    @Test func snapshotMapsToVolume() {
        #expect(Volumes.strippingSnapshot("disk3s1s1") == "disk3s1")
        #expect(Volumes.strippingSnapshot("disk3s5") == "disk3s5")
        #expect(Volumes.strippingSnapshot("disk10s2s1") == "disk10s2")
    }

    @Test func containerOfVolume() {
        #expect(Volumes.container(ofVolume: "disk3s5") == "disk3")
        #expect(Volumes.container(ofVolume: "disk12s1") == "disk12")
        #expect(Volumes.container(ofVolume: "disk3") == nil)
    }

    @Test func wholeDiskThroughContainerOrOwnName() {
        func volume(_ bsd: String, container: String?) -> VolumeInfo {
            VolumeInfo(name: bsd, mountPoint: "/\(bsd)", bsdName: bsd, fileSystem: "apfs", totalBytes: 0, freeBytes: 0,
                       availableBytes: nil, usedBytes: nil, isInternal: true, isEjectable: false, isEncrypted: false,
                       role: nil, container: container)
        }
        let containers = [APFSContainer(bsdName: "disk3", sizeBytes: 0, freeBytes: nil, physicalStores: ["disk0s2"], volumes: [])]
        #expect(Volumes.wholeDisk(of: volume("disk3s1", container: "disk3"), containers: containers) == "disk0")
        #expect(Volumes.wholeDisk(of: volume("disk6s1", container: nil), containers: containers) == "disk6")
        #expect(Volumes.wholeDisk(of: volume("", container: nil), containers: containers) == nil)
    }

    @Test func nameSearch() {
        let names = ["Macintosh HD", "Backup"]
        #expect(NameSearch.filter(names, query: "", names: { [$0] }) == names)
        #expect(NameSearch.filter(names, query: "macintosh", names: { [$0] }) == ["Macintosh HD"])
        #expect(NameSearch.filter(names, query: "zip", names: { [$0] }).isEmpty)
    }

    @Test func readSmoke() throws {
        let (volumes, containers) = Volumes.read()
        let root = try #require(volumes.first { $0.mountPoint == "/" })
        #expect(root.totalBytes > root.freeBytes && root.freeBytes > 0)
        #expect(root.usedBytes == root.totalBytes - root.freeBytes)
        let owners = containers.filter { $0.volumes.contains { $0.bsdName == root.bsdName } }
        #expect(owners.count == 1 && owners.first?.bsdName == root.container)
    }
}
