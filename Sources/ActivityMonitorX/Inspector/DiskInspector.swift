import AMXCore
import SwiftUI

/// The selected volume or physical disk from what the Disk screen reads; with none, the totals of all volumes.
struct DiskInspector: View {
    @Environment(DiskModel.self) private var disk

    var body: some View {
        Form {
            switch disk.selected {
            case .volume(let id)?: if let volume = disk.volumes.first(where: { $0.id == id }) { details(volume) } else { summary }
            case .disk(let id)?: if let physical = disk.disks.first(where: { $0.id == id }) { details(physical) } else { summary }
            case nil: summary
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var summary: some View {
        // The volumes of one APFS container share its space, so it counts once.
        let pools = Dictionary(disk.volumes.map { ($0.container ?? $0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        title("All Volumes")
        Section {
            LabeledContent("Volumes", value: disk.volumes.count.formatted())
            LabeledContent("Capacity", value: Metric.bytes(pools.reduce(0) { $0 + Double($1.totalBytes) }))
            LabeledContent("Available", value: Metric.bytes(pools.reduce(0) { $0 + Double($1.available) }))
            LabeledContent("Physical disks", value: disk.disks.count.formatted())
        } header: {
            Text("Space")
        } footer: {
            Text("Click a disk or a volume to see its details.")
        }
        .monospacedDigit()
    }

    @ViewBuilder private func details(_ volume: VolumeInfo) -> some View {
        title(volume.name)
        CardSection("Space") {
            LabeledContent("Capacity", value: Metric.bytes(Double(volume.totalBytes)))
            LabeledContent("Used", value: Metric.bytes(Double(volume.used)))
            LabeledContent("Available", value: Metric.bytes(Double(volume.available)))
        }
        .monospacedDigit()
        CardSection("Volume") {
            LabeledContent("File system", value: volume.role.map { "\(volume.fileSystem.uppercased()), \($0)" } ?? volume.fileSystem.uppercased())
            LabeledContent("Mount point", value: volume.mountPoint)
            LabeledContent("Device", value: volume.bsdName.isEmpty ? "None" : volume.bsdName)
            LabeledContent("Location", value: volume.isInternal ? "Internal" : "External")
            LabeledContent("Encrypted", value: volume.isEncrypted ? "Yes" : "No")
        }
        if let id = Volumes.wholeDisk(of: volume, containers: disk.containers),
           let physical = disk.disks.first(where: { $0.id == id }) {
            CardSection("Disk") {
                LabeledContent("Name", value: physical.model ?? physical.bsdName)
                health(physical)
            }
        }
    }

    @ViewBuilder private func details(_ physical: PhysicalDisk) -> some View {
        title(physical.model ?? physical.bsdName)
        CardSection("Disk") {
            LabeledContent("Capacity", value: Metric.bytes(Double(physical.sizeBytes)))
            LabeledContent("Device", value: physical.bsdName)
            if let name = physical.protocolName { LabeledContent("Connection", value: name) }
            LabeledContent("Location", value: physical.isInternal ? "Internal" : "External")
            health(physical)
        }
    }

    /// SMART state and the read and write rates now.
    @ViewBuilder private func health(_ physical: PhysicalDisk) -> some View {
        LabeledContent("Health") { SmartStatus(health: disk.health[physical.bsdName]) }
        if let rate = disk.perDisk[physical.bsdName] {
            LabeledContent("Read now", value: Metric.disk.format(rate.readBps)).monospacedDigit()
            LabeledContent("Write now", value: Metric.disk.format(rate.writeBps)).monospacedDigit()
        }
    }

    private func title(_ text: String) -> some View {
        Section { Text(text).font(.title3.bold()).overlayScrollers() }
    }
}
