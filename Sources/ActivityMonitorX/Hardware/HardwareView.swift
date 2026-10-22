import AMXCore
import SwiftUI

/// The Mac at a glance, over the full inventory.
/// Read once on the first open and on Refresh only. Content layer: no glass.
struct HardwareView: View {
    @Environment(HardwareModel.self) private var hardware
    @Environment(Selection.self) private var selection

    var body: some View {
        content
            .navigationTitle("Hardware")
            .navigationSubtitle(subtitle)
            .task { await hardware.loadOnce() }
            .onChange(of: selection.refreshes) { Task { await hardware.refresh() } }
    }

    @ViewBuilder private var content: some View {
        if hardware.nodes.isEmpty {
            switch hardware.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Cannot Read Hardware", systemImage: "exclamationmark.triangle", description: Text(message))
            case .empty, .ready:
                ContentUnavailableView("No Hardware Information", systemImage: "cpu")
            }
        } else {
            VStack(spacing: 0) {
                overview.padding()
                Divider()
                inventory
            }
        }
    }

    /// "Updating…" over a shown capture; a failed Refresh keeps the last capture and says why.
    private var subtitle: String {
        switch hardware.state {
        case .loading where hardware.capturedAt != nil: "Updating…"
        case .failed(let message) where !hardware.nodes.isEmpty: message
        default: hardware.capturedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        }
    }

    // MARK: Overview

    private var overview: some View {
        HStack(alignment: .top, spacing: 24) {
            if let chip = hardware.chip {
                ChipDiagram(chip: chip, gpuCores: hardware.value("sppci_cores").flatMap { Int($0) })
                    .frame(width: 300)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hardware.value("machine_name") ?? "Mac").font(.title2.weight(.semibold))
                        if let model = hardware.value("machine_model") { Text(model).foregroundStyle(.secondary) }
                    }
                    .gridCellColumns(2)
                    .padding(.bottom, 6)
                }
                if let volume = hardware.startup { storage(volume) }
                let displays = hardware.values("_spdisplays_resolution")
                if !displays.isEmpty {
                    GridRow {
                        Text("Displays").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(displays.indices, id: \.self) { Text("\(displays[$0].name), \(displays[$0].value)") }
                        }
                    }
                }
                if let capacity = hardware.value("sppower_battery_health_maximum_capacity") {
                    detail("Battery", ["Maximum capacity \(capacity)",
                                       hardware.value("sppower_battery_cycle_count").map { "\($0) cycles" },
                                       hardware.value("sppower_battery_health").map { "Condition \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    /// The startup volume's used space; orange under the Disk screen's low-space rule.
    private func storage(_ volume: VolumeInfo) -> some View {
        GridRow {
            Text("Storage").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(volume.used, volume.totalBytes)), total: Double(max(volume.totalBytes, 1)))
                    .tint(volume.lowSpace ? .orange : nil)
                    .frame(width: 240)
                    .accessibilityLabel(volume.lowSpace ? "Low free space" : "Used")
                Text("\(volume.name): \(Metric.bytes(Double(volume.freeBytes))) free of \(Metric.bytes(Double(volume.totalBytes))) (purgeable not included)")
                    .monospacedDigit()
            }
        }
    }

    // MARK: Inventory

    private var inventory: some View {
        Table(of: HardwareRow.self) {
            TableColumn("Name", value: \.name)
                .width(min: 160, ideal: 280)
            TableColumn("Value", value: \.value)
        } rows: {
            InventoryRows(rows: hardware.rows, hardware: hardware)
        }
    }
}

/// Rows at any depth, each disclosure bound to `HardwareModel.expanded`.
private struct InventoryRows: TableRowContent {
    let rows: [HardwareRow]
    let hardware: HardwareModel

    var tableRowBody: some TableRowContent<HardwareRow> {
        ForEach(rows) { row in
            if let children = row.children {
                DisclosureTableRow(row, isExpanded: expanded(row.id)) {
                    InventoryRows(rows: children, hardware: hardware)
                }
            } else {
                TableRow(row)
            }
        }
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(get: { hardware.expanded.contains(id) },
                set: { if $0 { hardware.expanded.insert(id) } else { hardware.expanded.remove(id) } })
    }
}
