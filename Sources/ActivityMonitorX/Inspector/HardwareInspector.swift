import AMXCore
import AppKit
import SwiftUI

/// The selected Hardware inventory row: its name, value and section, with Copy; with none, a summary of the Mac.
struct HardwareInspector: View {
    @Environment(HardwareModel.self) private var hardware

    var body: some View {
        let path = hardware.selected.map { HardwareRow.path(to: $0, in: hardware.rows) } ?? []
        if let row = path.last {
            Form {
                Section { Text(row.name).font(.title3.bold()).overlayScrollers() }
                Section("Value") {
                    Text(row.value.isEmpty ? "None" : row.value).textSelection(.enabled)
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(row.name): \(row.value)", forType: .string)
                    }
                    .help("Copy the name and the value")
                }
                if path.count > 1 {
                    Section("Section") { Text(path.dropLast().map(\.name).joined(separator: " > ")) }
                }
            }
            .formStyle(.grouped)
        } else {
            summary
        }
    }

    /// With no row selected, the Mac at a glance: chip, memory, thermal state and uptime, read again every 10 s.
    private var summary: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 10)) { _ in summaryForm }
    }

    private var summaryForm: some View {
        Form {
            Section { Text(hardware.value("machine_name") ?? "Mac").font(.title3.bold()).overlayScrollers() }
            Section {
                if let chip = hardware.chip {
                    LabeledContent("Chip", value: chip.name)
                    LabeledContent("Cores", value: chip.clusters.map { "\($0.cores) \($0.name)" }.joined(separator: ", "))
                    LabeledContent("Memory", value: Int64(chip.memory).formatted(.byteCount(style: .memory)))
                }
                // As System Health in Apps shows them.
                LabeledContent("Thermal State", value: SystemState.thermal(ProcessInfo.processInfo.thermalState.rawValue).capitalized)
                LabeledContent("Uptime", value: Duration.seconds(ProcessInfo.processInfo.systemUptime)
                    .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
            } header: {
                Text("Summary")
            } footer: {
                Text("Click a row to see its details.")
            }
        }
        .formStyle(.grouped)
    }
}
