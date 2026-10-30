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
        CardSection("Space", summary: Text("\(Metric.bytes(pools.reduce(0) { $0 + Double($1.available) })) available"), footer: Text("Click a disk or a volume to see its details.")) {
            LabeledContent("Volumes", value: disk.volumes.count.formatted())
            LabeledContent("Capacity", value: Metric.bytes(pools.reduce(0) { $0 + Double($1.totalBytes) }))
            LabeledContent("Available", value: Metric.bytes(pools.reduce(0) { $0 + Double($1.available) }))
            LabeledContent("Physical disks", value: disk.disks.count.formatted())
        }
        .monospacedDigit()
    }

    @ViewBuilder private func details(_ volume: VolumeInfo) -> some View {
        InspectorTitle(volume.name)
        CardSection("Space", summary: Text("\(Metric.bytes(Double(volume.available))) available")) {
            LabeledContent("Capacity", value: Metric.bytes(Double(volume.totalBytes)))
            LabeledContent("Used", value: Metric.bytes(Double(volume.used)))
            LabeledContent("Available", value: Metric.bytes(Double(volume.available)))
        }
        .monospacedDigit()
        CardSection("Volume", summary: Text(volume.fileSystem.uppercased())) {
            LabeledContent("File system", value: volume.role.map { "\(volume.fileSystem.uppercased()), \($0)" } ?? volume.fileSystem.uppercased())
            LabeledContent("Mount point", value: volume.mountPoint)
            LabeledContent("Device", value: volume.bsdName.isEmpty ? "None" : volume.bsdName)
            LabeledContent("Location", value: volume.isInternal ? "Internal" : "External")
            LabeledContent("Encrypted", value: volume.isEncrypted ? "Yes" : "No")
        }
        if let id = Volumes.wholeDisk(of: volume, containers: disk.containers),
           let physical = disk.disks.first(where: { $0.id == id }) {
            CardSection("Disk", summary: Text(SmartStatus.word(disk.health[physical.bsdName]))) {
                LabeledContent("Name", value: physical.model ?? physical.bsdName)
                health(physical)
            }
        }
    }

    @ViewBuilder private func details(_ physical: PhysicalDisk) -> some View {
        InspectorTitle(physical.model ?? physical.bsdName)
        CardSection("Disk", summary: Text(Metric.bytes(Double(physical.sizeBytes)))) {
            LabeledContent("Capacity", value: Metric.bytes(Double(physical.sizeBytes)))
            LabeledContent("Device", value: physical.bsdName)
            if let name = physical.protocolName { LabeledContent("Connection", value: name) }
            LabeledContent("Location", value: physical.isInternal ? "Internal" : "External")
            health(physical)
        }
        if let h = disk.health[physical.bsdName] {
            CardSection("SMART", summary: Text("\(Units.percent(Double(h.percentageUsed))) used")) {
                LabeledContent("Percentage used", value: Units.percent(Double(h.percentageUsed)))
                LabeledContent("Available spare", value: "\(Units.percent(Double(h.availableSpare))), threshold \(Units.percent(Double(h.spareThreshold)))")
                LabeledContent("Media errors", value: h.mediaErrors.formatted())
                LabeledContent("Unsafe shutdowns", value: h.unsafeShutdowns.formatted())
                LabeledContent("Temperature", value: h.temperatureCelsius.map(Units.celsius) ?? "No data")
                LabeledContent("Data read", value: Metric.bytes(Double(h.dataReadBytes)))
                LabeledContent("Data written", value: Metric.bytes(Double(h.dataWrittenBytes)))
                LabeledContent("Power-on hours", value: h.powerOnHours.formatted())
                LabeledContent("Power cycles", value: h.powerCycles.formatted())
            }
            .monospacedDigit()
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
}
