import AMXCore
import AppKit
import SwiftUI

/// The selected Hardware inventory row: its name, value and section, with Copy.
struct HardwareInspector: View {
    @Environment(HardwareModel.self) private var hardware

    var body: some View {
        let path = hardware.selected.map { HardwareRow.path(to: $0, in: hardware.rows) } ?? []
        if let row = path.last {
            Form {
                Section { Text(row.name).font(.title3.bold()) }
                Section("Value") {
                    Text(row.value.isEmpty ? "None" : row.value).textSelection(.enabled)
                    Button("Copy") {
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
            ContentUnavailableView("No Selection", systemImage: "cpu", description: Text("Click a row to see its details."))
        }
    }
}
