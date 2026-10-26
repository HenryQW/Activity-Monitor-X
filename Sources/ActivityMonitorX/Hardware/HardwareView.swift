import AMXCore
import SwiftUI

/// The Mac at a glance, over the full inventory. The search filters the inventory and opens the rows that hold a match;
/// its selection is the inspector's. Read once on the first open and on Refresh only. Content layer: no glass.
struct HardwareView: View {
    @Environment(HardwareModel.self) private var hardware
    @Environment(Selection.self) private var selection
    /// The content column's width, the most the board's chip can take.
    private let _width = State(initialValue: 1000.0)

    var body: some View {
        content
            .screenTitle("Hardware", subtitle: Text(subtitle), icon: .symbol("cpu"))
            .task { await hardware.loadOnce() }
            .task { await hardware.sampleLive() }
            .onChange(of: selection.refreshes) { Task { await hardware.refresh() } }
            // A drive plugged in or out reads the inventory again, so its part and its rows come and go together.
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in Task { await hardware.refresh() } }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in Task { await hardware.refresh() } }
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
                // The table takes the width it is offered, so it measures the column; the overview can be wider than that.
                inventory.onGeometryChange(for: Double.self) { $0.size.width } action: { _width.wrappedValue = $0 }
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

    /// The board at every width: the chip's columns shrink and the cells go under the chip where the column is narrow
    /// (beside the inspector the content can be 380 pt wide).
    @ViewBuilder private var overview: some View {
        if let chip = hardware.chip {
            HardwareBoard(chip: chip, hardware: hardware, width: _width.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Inventory

    private var inventory: some View {
        let rows = HardwareRow.filter(hardware.rows, query: selection.search).rows
        return ScrollViewReader { proxy in
            Table(of: HardwareRow.self, selection: Bindable(hardware).selected) {
                // One icon column: symbols of every width centre in the same slot, and a row with none keeps the slot
                // empty, so the names at one level line up.
                TableColumn("Name") { row in
                    HStack(spacing: 4) {
                        Color.clear.frame(width: 18, height: 1)
                            .overlay { if let symbol = row.symbol { Image(systemName: symbol).foregroundStyle(.secondary).fixedSize() } }
                        Text(row.name)
                    }
                }
                .width(min: 160, ideal: 280)
                TableColumn("Value", value: \.value)
            } rows: {
                InventoryRows(rows: rows, hardware: hardware)
            }
            // A part chosen on the board scrolls its row to the top, so its rows show, once the opened rows are in the table.
            .onChange(of: hardware.reveal) { _, id in
                guard let id else { return }
                hardware.reveal = nil
                Task { withAnimation(Motion.smooth(0.3)) { proxy.scrollTo(id, anchor: .top) } }
            }
        }
        .overlay { if rows.isEmpty { ContentUnavailableView.search(text: selection.search) } }
        .onChange(of: selection.search) { _, query in hardware.expand(for: query) }
        // Leaving the screen clears the search.
        .onDisappear { hardware.expand(for: "") }
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
