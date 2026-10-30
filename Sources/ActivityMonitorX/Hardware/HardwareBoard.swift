import AMXCore
import SwiftUI

/// A part of the chip or a board cell; a click selects its inventory row.
enum BoardPart: Hashable {
    case cluster(Int), gpu, memory, battery
    /// The startup volume or an external drive's, by its mount point.
    case volume(String)
    /// A connected display, by its inventory row.
    case display(HardwareRow.ID)
}

extension HardwareModel {
    /// "48 GB LPDDR5"; the type only where the inventory gives it.
    func memory(_ chip: ChipInfo) -> String {
        ([Int64(chip.memory).formatted(.byteCount(style: .memory))] + [dimmType].compactMap { $0 }).joined(separator: " ")
    }

    /// Each connected display's row and its resolution, "1512 x 982, 120 Hz".
    var displays: [(row: HardwareRow, resolution: String)] {
        HardwareRow.rows(holding: "_spdisplays_resolution", in: rows).map { ($0.row, HardwareInventory.resolution($0.property.value)) }
    }

    /// The battery health row (maximum capacity, cycle count, condition); nil on a Mac with no battery.
    var batteryRow: HardwareRow? { HardwareRow.rows(holding: "sppower_battery_health_maximum_capacity", in: rows).first?.row }

    /// "100% capacity", "8 cycles", "Condition Good": the board and the details say the same.
    var batteryFacts: [String] {
        guard let battery = batteryRow else { return [] }
        return [property("sppower_battery_health_maximum_capacity", of: battery).map { "\($0) capacity" },
                property("sppower_battery_cycle_count", of: battery).map { "\($0) cycles" },
                property("sppower_battery_health", of: battery).map { "Condition \($0)" }].compactMap { $0 }
    }

    /// The startup volume and the external drives the inventory names, without disk images (a mounted backup or
    /// installer is not a drive).
    var boardVolumes: [VolumeInfo] {
        volumes.filter { volume in
            guard volume.mountPoint != "/" else { return true }
            guard let row = HardwareRow.rows(holding: "mount_point", value: volume.mountPoint, in: rows).first?.row else { return false }
            // The protocol is on the drive row above the volume (SCR-25).
            let images = Set(HardwareRow.rows(holding: "protocol", value: "Disk Image", in: rows).map(\.row.id))
            return !HardwareRow.path(to: row.id, in: rows).contains { images.contains($0.id) }
        }
    }

    /// A Storage drive row's physical disk, found through its first volume; nil for any other row.
    func drive(_ row: HardwareRow) -> PhysicalDisk? {
        guard row.id.hasPrefix("Storage/"), row.id.dropFirst(8).contains("/") == false,
              // A hidden volume (Data) is not among the volumes read: the first one that is.
              let volume = HardwareRow.rows(holding: "mount_point", in: row.children ?? [])
                  .lazy.compactMap({ m in self.allVolumes.first { $0.mountPoint == m.property.value } }).first,
              let bsd = Volumes.wholeDisk(of: volume, containers: containers) else { return nil }
        return disks.first { $0.bsdName == bsd }
    }

    /// The parts with data and the row each one selects, for `partRows`. The clusters share the Processors row: the
    /// inventory has none per cluster.
    func parts() -> [(part: BoardPart, row: HardwareRow.ID)] {
        let find = { (key: String) in HardwareRow.rows(holding: key, in: self.rows).first }
        var parts: [(part: BoardPart, row: HardwareRow.ID)] = []
        if let processors = find("number_processors")?.property.id {
            parts += (chip?.clusters.indices ?? 0..<0).map { (.cluster($0), processors) }
        }
        if let gpu = find("sppci_cores")?.row.id { parts.append((.gpu, gpu)) }
        // A memory node of one property is one row with no key; the overview's memory size is the next best row.
        if let memory = find("SPMemoryDataType")?.row.id ?? find("physical_memory")?.property.id { parts.append((.memory, memory)) }
        for volume in boardVolumes {
            if let row = HardwareRow.rows(holding: "mount_point", value: volume.mountPoint, in: rows).first?.row.id {
                parts.append((.volume(volume.mountPoint), row))
            }
        }
        parts += displays.map { (.display($0.row.id), $0.row.id) }
        if let battery = batteryRow?.id { parts.append((.battery, battery)) }
        return parts
    }

    /// The parts that show the selected row: those whose row is that row or the nearest row above it. Of the clusters
    /// that share the Processors row, the one clicked last; all of them when the row was chosen in the table.
    var selectedParts: Set<BoardPart> {
        guard let selected else { return [] }
        let parts = partRows
        guard let row = HardwareRow.path(to: selected, in: rows).last(where: { row in parts.contains { $0.row == row.id } }) else {
            return []
        }
        let matches = parts.filter { $0.row == row.id }.map(\.part)
        return clickedPart.map(matches.contains) == true ? [clickedPart!] : Set(matches)
    }

    /// Selects the part's row and opens the rows down to it and its own, so its rows show; the table scrolls to it.
    func show(_ part: BoardPart) {
        guard let row = partRows.first(where: { $0.part == part })?.row else { return }
        clickedPart = part
        open(HardwareRow.path(to: row, in: rows).map(\.id))
        selected = row
        reveal = row
    }

    func property(_ key: String, of row: HardwareRow) -> String? {
        row.children?.first { $0.id.hasSuffix("=" + key) }?.value
    }
}

/// The Mac at a glance, at every width: the chip and, beside it, one cell for each part with
/// data, all the same size: the startup volume, the battery, each connected display, each external drive, as a live
/// shape, its name and one fact. Two cells to a row, a third column past three rows. Chip and cells are centred as one
/// group of one height; where the width is short, the cells go under the chip, as wide as it. Each cell is a button.
struct HardwareBoard: View {
    let chip: ChipInfo
    let hardware: HardwareModel
    @Environment(\.colorSchemeContrast) private var contrast
    /// The content column's width; the chip takes at most that, less the paddings.
    let width: Double
    @Environment(AlertsModel.self) private var alerts
    /// The chip's width: cells under the chip share it, so both rows are as wide.
    private let _chipWidth = State(initialValue: 0.0)

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Layout.padding) {
                VStack(alignment: .leading, spacing: Layout.gap) {
                    Text(hardware.value("machine_name") ?? "Mac").font(.headline)
                    Text([hardware.value("machine_model"), chip.name, "\(hardware.memory(chip)) unified memory"].compactMap { $0 }
                        .joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                board
            }
            // With the box's own small inset, the layout's padding from its edge.
            .padding(Layout.inset)
        }
    }

    private var board: some View {
        let selected = hardware.selectedParts
        let volumes = hardware.boardVolumes
        let parts = volumes.filter { $0.mountPoint == "/" }.map { BoardPart.volume($0.mountPoint) }
            + (hardware.batteryRow == nil ? [] : [.battery]) + hardware.displays.map { .display($0.row.id) }
            + volumes.filter { $0.mountPoint != "/" }.map { .volume($0.mountPoint) }
        let columns = min(3, max(2, (parts.count + 2) / 3))
        let cells = { (cellWidth: Double, cellHeight: Double?) in
            Grid(horizontalSpacing: Layout.inset, verticalSpacing: Layout.inset) {
                ForEach(Array(stride(from: 0, to: parts.count, by: columns)), id: \.self) { start in
                    GridRow {
                        ForEach(parts[start..<min(start + columns, parts.count)], id: \.self) {
                            cell($0, volumes: volumes, selected: selected)
                                .frame(width: cellWidth)
                                .frame(minHeight: cellHeight ?? 38, maxHeight: cellHeight ?? .infinity)
                        }
                    }
                }
            }
        }
        let diagram = ChipDiagram(chip: chip, hardware: hardware, maxWidth: width - 64)
            .onGeometryChange(for: Double.self) { $0.size.width } action: { _chipWidth.wrappedValue = $0 }
        // Under the chip the cells share its width, also below 196 pt: their text truncates and the hint has it in full.
        let under = max(80, (_chipWidth.wrappedValue - Layout.inset * Double(columns - 1)) / Double(columns))
        return ViewThatFits(in: .horizontal) {
            // Side by side, both take the taller one's height: the chip spreads its rows, the cells grow past 38 pt.
            HStack(spacing: Layout.padding) {
                diagram.frame(maxHeight: .infinity)
                cells(196, nil).frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Layout.padding) { diagram; cells(under, 38) }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func cell(_ part: BoardPart, volumes: [VolumeInfo], selected: Set<BoardPart>) -> some View {
        switch part {
        case .volume(let mountPoint):
            if let volume = volumes.first(where: { $0.mountPoint == mountPoint }) { storage(volume, selected: selected) }
        case .display(let id):
            if let display = hardware.displays.first(where: { $0.row.id == id }) {
                let brightness = hardware.brightness[id]
                let level = brightness.map { Units.percent($0 * 100) }
                let size = display.resolution.components(separatedBy: ", ").first ?? display.resolution
                let builtIn = hardware.property("spdisplays_connection_type", of: display.row) == "Internal"
                // The built-in display's full name ("Built-in Liquid Retina XDR Display") does not fit a cell; the hint has it.
                self.cell(part, name: builtIn ? "Built-in Display" : display.row.name, fact: [size, level].compactMap { $0 }.joined(separator: ", "),
                          label: "Display, \(display.row.name)", value: [display.resolution, level.map { "\($0) brightness" }].compactMap { $0 }.joined(separator: ", "),
                          hint: "Show \(display.row.name) in the list" + (brightness == nil ? ". macOS does not report this display's brightness." : ""),
                          selected: selected) {
                    screen(brightness, builtIn: builtIn)
                }
            }
        case .battery:
            let facts = [chargeText].compactMap { $0 } + hardware.batteryFacts
            let cycles = hardware.batteryRow.flatMap { hardware.property("sppower_battery_cycle_count", of: $0) }.map { "\($0) cycles" }
            self.cell(.battery, name: "Battery", fact: [shortCharge, cycles].compactMap { $0 }.joined(separator: ", "),
                      label: "Battery", value: facts.joined(separator: ", "),
                      hint: "Show the battery in the list. " + facts.joined(separator: ", "), selected: selected) {
                BatteryShape(percent: hardware.charge?.percent.map(Double.init), charging: hardware.charge?.charging == true, level: chargeLevel)
            }
        case .cluster, .gpu, .memory:
            EmptyView()
        }
    }

    /// Flash chips filled to the used share, as the cores fill to their use; yellow under the Disk screen's low-space rule,
    /// red on the startup volume at the free space alert's level. The startup volume has two chips, an external drive one.
    private func storage(_ volume: VolumeInfo, selected: Set<BoardPart>) -> some View {
        let free = Metric.bytes(Double(volume.freeBytes)), total = Metric.bytes(Double(volume.totalBytes))
        let share = Double(min(volume.used, volume.totalBytes)) / Double(max(volume.totalBytes, 1))
        // Text with the colour: the yellow is never the only cue.
        let low = volume.lowSpace ? ", low" : ""
        let startup = volume.mountPoint == "/"
        let color = ChipDiagram.status(volume.spaceLevel(alerts.rules.freeSpace))
        return cell(.volume(volume.mountPoint), name: volume.name, fact: "\(free) free\(low)", label: "Storage, \(volume.name)",
                    value: "\(free) free of \(total)\(volume.lowSpace ? ", low free space" : "")",
                    hint: "Show \(volume.name) in the list" + (startup ? ". Free space does not include purgeable space." : ""),
                    selected: selected) {
            FlashChips(count: startup ? 2 : 1, share: share, color: color)
        }
    }

    /// A screen filled to its brightness, as the cores fill to their use: a laptop lid on its base for the built-in
    /// display, a monitor on a stand for another. No fill where macOS does not report the brightness.
    private func screen(_ brightness: Double?, builtIn: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        return VStack(spacing: 0) {
            shape.fill(PartStyle.package)
                .overlay(alignment: .bottom) {
                    if let brightness {
                        GeometryReader { proxy in
                            ZStack(alignment: .top) {
                                Rectangle().fill(.tint.opacity(0.28))
                                Rectangle().fill(.tint).frame(height: 1)
                            }
                            .frame(height: proxy.size.height * brightness)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(trace, lineWidth: 1.5) }
                .frame(width: 24, height: 15)
            if builtIn {
                RoundedRectangle(cornerRadius: 1).fill(trace).frame(width: 30, height: 2.5)
            } else {
                Rectangle().fill(trace).frame(width: 2, height: 3)
                RoundedRectangle(cornerRadius: 1).fill(trace).frame(width: 12, height: 2)
            }
        }
    }

    /// "62% charge", with ", charging" or ", low" (yellow at 20 % and red at 10 %, as text too); nil with no reading.
    private var chargeText: String? { shortCharge.map { $0.replacingOccurrences(of: "%", with: "% charge") } }

    /// "62%", with ", charging" or ", low"; nil with no reading.
    private var shortCharge: String? {
        guard let charge = hardware.charge, let percent = charge.percent else { return nil }
        return Units.percent(Double(percent)) + (charge.charging ? ", charging" : chargeLevel > 0 ? ", low" : "")
    }

    private var chargeLevel: Int { BatteryShape.level(percent: hardware.charge?.percent, charging: hardware.charge?.charging == true) }

    /// A cell, 196 pt wide and at least 38 pt high beside the chip, 38 pt high under it: the shape in a 32 by 22 box, the name and one fact; a button with the accent outline while
    /// it shows the selected row; one accessibility element.
    private func cell(_ part: BoardPart, name: String, fact: String, label: String, value: String, hint: String,
                      selected: Set<BoardPart>, @ViewBuilder shape: () -> some View) -> some View {
        Button { hardware.show(part) } label: {
            HStack(spacing: Layout.inset) {
                shape().frame(width: 32, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).fontWeight(.semibold)
                    Text(fact).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .partCell(selected: selected.contains(part))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(selected.contains(part) ? .isSelected : [])
    }

    private var trace: Color { PartStyle.trace(contrast) }
}
