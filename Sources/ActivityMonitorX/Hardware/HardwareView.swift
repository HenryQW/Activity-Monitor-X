import AMXCore
import SwiftUI

/// The Mac at a glance, over the full inventory. The search filters the inventory and opens the rows that hold a match;
/// its selection is the inspector's. Read once on the first open and on Refresh only. Content layer: no glass.
struct HardwareView: View {
    @Environment(HardwareModel.self) private var hardware
    @Environment(Selection.self) private var selection

    var body: some View {
        content
            .screenTitle("Hardware", subtitle: Text(subtitle), icon: .symbol("cpu"))
            .task { await hardware.loadOnce() }
            .task { await hardware.sampleLive() }
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

    /// The details go beside the chip where both fit, else under it: beside the inspector the content can be 380 pt wide.
    /// The details ask for 330 pt beside the chip (the Storage bar and its label) and wrap their text to the width they get.
    private var overview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                chip
                details.frame(minWidth: 330, idealWidth: 330, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) {
                chip
                details
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var chip: some View {
        if let chip = hardware.chip {
            LiveChip(chip: chip, gpuCores: hardware.value("sppci_cores").flatMap { Int($0) }, hardware: hardware)
                .frame(width: 300)
        }
    }

    private var details: some View {
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
        // The full height: the text wraps instead of truncating.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    /// The startup volume's used space; yellow under the Disk screen's low-space rule.
    private func storage(_ volume: VolumeInfo) -> some View {
        GridRow {
            Text("Storage").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(volume.used, volume.totalBytes)), total: Double(max(volume.totalBytes, 1)))
                    .tint(volume.lowSpace ? .yellow : nil)
                    .frame(width: 240)
                    .accessibilityLabel(volume.lowSpace ? "Low free space" : "Used")
                Text("\(volume.name): \(Metric.bytes(Double(volume.freeBytes))) free of \(Metric.bytes(Double(volume.totalBytes))) (purgeable not included)")
                    .monospacedDigit()
            }
        }
    }

    // MARK: Inventory

    private var inventory: some View {
        let rows = HardwareRow.filter(hardware.rows, query: selection.search).rows
        return Table(of: HardwareRow.self, selection: Bindable(hardware).selected) {
            TableColumn("Name", value: \.name)
                .width(min: 160, ideal: 280)
            TableColumn("Value", value: \.value)
        } rows: {
            InventoryRows(rows: rows, hardware: hardware)
        }
        .overlay { if rows.isEmpty { ContentUnavailableView.search(text: selection.search) } }
        .onChange(of: selection.search) { _, query in hardware.expand(for: query) }
        // Leaving the screen clears the search.
        .onDisappear { hardware.expand(for: "") }
    }
}

/// The chip with its usage: only this view reads the 2 s readings, so they do not rebuild the screen.
private struct LiveChip: View {
    let chip: ChipInfo
    let gpuCores: Int?
    let hardware: HardwareModel

    var body: some View {
        ChipDiagram(chip: chip, gpuCores: gpuCores, cpuUsage: hardware.cpuUsage, gpuUsage: hardware.gpuUsage)
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
