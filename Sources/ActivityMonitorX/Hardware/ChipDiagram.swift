import AMXCore
import SwiftUI

/// The chip as glyphs on one grid of columns: each CPU core is the `cpu` symbol, filled from the bottom to its use, the
/// clusters side by side with one empty column between them; the GPU cores take the same columns, so the rows line up.
/// macOS has no GPU symbol: a GPU core is a block of lanes, as it looks on the die, and all fill to the one GPU total.
/// Memory is one `memorychip` symbol beside them, filled from the left to the memory used. Each cluster, the GPU and
/// the memory is a button and one accessibility element that selects its inventory row. Only this view reads the 2 s
/// readings, so they do not rebuild the screen. No animation on a read.
struct ChipDiagram: View {
    let chip: ChipInfo
    let hardware: HardwareModel
    /// The width the chip may take: the columns shrink to fit it, from 20 pt down to 9 pt.
    var maxWidth = Double.infinity
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(AlertsModel.self) private var alerts
    @Environment(MenuBarReadout.self) private var readout

    static let gap = 3.0, padding = 10.0, spacing = 14.0, memoryWidth = 72.0

    /// The CPU cores and one empty column between clusters; with no CPU cores (a virtual machine), the GPU's, up to 16.
    static func columns(_ chip: ChipInfo, gpuCores: Int?) -> Int {
        let cpu = chip.clusters.reduce(0) { $0 + $1.cores } + max(0, chip.clusters.count - 1)
        return cpu > 0 ? cpu : max(1, min(gpuCores ?? 1, 16))
    }

    var body: some View {
        let gpuCores = hardware.gpuCores
        let columns = Self.columns(chip, gpuCores: gpuCores)
        let room = maxWidth - 2 * Self.padding - Self.spacing - Self.memoryWidth + Self.gap
        let slot = min(20, max(9, room / Double(columns) - Self.gap))
        let selected = hardware.selectedParts
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        let textWidth = { (text: String) in (text as NSString).size(withAttributes: [.font: font]).width }
        // Every cluster has its name and the percent on one line, or every cluster has two lines, so the cores line up.
        let oneLine = chip.clusters.allSatisfy { Double($0.cores) * (slot + Self.gap) - Self.gap >= textWidth($0.name) + textWidth("100 %") + 6 }
        HStack(alignment: .top, spacing: Self.spacing) {
            // A taller chip (beside more cells) puts the space between the CPU and the GPU rows.
            VStack(alignment: .leading, spacing: 0) {
                // The empty column between clusters.
                HStack(alignment: .top, spacing: slot + 2 * Self.gap) {
                    ForEach(chip.clusters.indices, id: \.self) { cluster($0, slot: slot, oneLine: oneLine, selected: selected.contains(.cluster($0))) }
                }
                if let gpuCores, gpuCores > 0 {
                    Spacer(minLength: 10)
                    gpu(gpuCores, columns: columns, slot: slot, selected: selected.contains(.gpu))
                }
            }
            memory(slot: slot, selected: selected.contains(.memory))
        }
        .padding(Self.padding)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8)
            shape.fill(Color(nsColor: .quaternarySystemFill))
                .overlay { shape.strokeBorder(Color(nsColor: increased ? .secondaryLabelColor : .separatorColor)) }
        }
        .fixedSize(horizontal: true, vertical: false)
        .font(.caption)
        .monospacedDigit()
    }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    private var increased: Bool { contrast == .increased }

    /// The status role (DESIGN.md): yellow at a rule's warning level, red at its critical level, else the accent.
    static func status(_ level: Int) -> Color { level >= 2 ? .red : level == 1 ? .yellow : .accentColor }

    /// Cores and the GPU follow the system CPU rule (SET-7); the accent while the rule is off.
    private func cpuLevel(_ usage: Double?) -> Int {
        let rule = alerts.rules.systemCPU
        guard rule.enabled, let usage else { return 0 }
        return usage >= Double(rule.critical) ? 2 : usage >= Double(rule.warning) ? 1 : 0
    }

    /// A part as a button, with the accent outline while it shows the selected row.
    private func button(_ part: BoardPart, label: String, value: String, hint: String, selected: Bool,
                        @ViewBuilder content: () -> some View) -> some View {
        Button { hardware.show(part) } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.tint, lineWidth: 2).padding(-4).opacity(selected ? 1 : 0) }
            .help(hint)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The name, and the percent at the right edge of the cores under it.
    private func header(_ name: String, _ usage: Double?) -> some View {
        HStack(spacing: 2) {
            Text(name)
            Spacer(minLength: 2)
            if let usage { Text(Self.percent(usage)).foregroundStyle(.secondary) }
        }
        .lineLimit(1)
    }

    private func cluster(_ index: Int, slot: Double, oneLine: Bool, selected: Bool) -> some View {
        let cluster = chip.clusters[index]
        // Usage is shown only when the read covers every core of the chip.
        let usage = hardware.cpuUsage.count == chip.clusters.reduce(0) { $0 + $1.cores }
            ? Array(hardware.cpuUsage[chip.cpuIndexes(cluster: index)]) : []
        let average = usage.isEmpty ? nil : usage.reduce(0, +) / Double(usage.count)
        return button(.cluster(index), label: "\(cluster.name), \(cluster.cores) cores", value: average.map { "\(Self.percent($0)) busy" } ?? "",
                      hint: "Show the \(cluster.name) cores in the list", selected: selected) {
            VStack(alignment: .leading, spacing: 4) {
                if oneLine {
                    header(cluster.name, average)
                } else {
                    // A narrow cluster ("Efficiency" over two cores): the name may run into the empty column after it.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cluster.name)
                        Text(average.map(Self.percent) ?? " ").foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .frame(width: Double(cluster.cores) * (slot + Self.gap) - Self.gap, alignment: .leading)
                }
                HStack(spacing: Self.gap) {
                    ForEach(0..<cluster.cores, id: \.self) { i in
                        let name = "\(cluster.name) core \(i + 1)"
                        Glyph(name: "cpu", level: usage.isEmpty ? 0 : usage[i] / 100, color: Self.status(cpuLevel(usage.isEmpty ? 0 : usage[i])),
                              size: slot * 0.88)
                            .frame(width: slot, height: slot)
                            .help(usage.isEmpty ? name : "\(name): \(Self.percent(usage[i]))")
                    }
                }
            }
            .frame(width: Double(cluster.cores) * (slot + Self.gap) - Self.gap)
        }
    }

    /// The GPU cores in rows as long as the CPU row; all fill to the total, as macOS gives no use per GPU core.
    private func gpu(_ count: Int, columns: Int, slot: Double, selected: Bool) -> some View {
        let usage = hardware.gpuUsage
        let perRow = min(count, columns), color = Self.status(cpuLevel(usage))
        return button(.gpu, label: "GPU, \(count) cores", value: usage.map { "\(Self.percent($0)) busy" } ?? "",
                      hint: usage.map { "Show the GPU in the list. GPU: \(Self.percent($0)); macOS gives one total for all GPU cores." }
                          ?? "Show the GPU in the list", selected: selected) {
            VStack(alignment: .leading, spacing: 4) {
                header("GPU", usage)
                VStack(alignment: .leading, spacing: Self.gap) {
                    ForEach(0..<(count + perRow - 1) / perRow, id: \.self) { row in
                        HStack(spacing: Self.gap) {
                            ForEach(row * perRow..<min(count, (row + 1) * perRow), id: \.self) { _ in
                                GPUCore(level: (usage ?? 0) / 100, color: color, increased: increased).frame(width: slot, height: slot)
                            }
                        }
                    }
                }
            }
            .frame(width: Double(perRow) * (slot + Self.gap) - Self.gap)
        }
    }

    /// One chip symbol for the memory, as wide as its header, filled from the left to the memory used in the colour of the
    /// system's memory pressure, as the menu bar dial shows it.
    private func memory(slot: Double, selected: Bool) -> some View {
        let usage = hardware.memoryUsage
        let color = Self.status(readout.percents.map { $0.level == 4 ? 2 : $0.level == 2 ? 1 : 0 } ?? 0)
        let value = [hardware.memory(chip), usage.map { "\(Self.percent($0)) used" }].compactMap { $0 }.joined(separator: ", ")
        return button(.memory, label: "Unified memory", value: value, hint: "Show the memory in the list", selected: selected) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Memory")
                    if let usage { Text(Self.percent(usage)).foregroundStyle(.secondary) }
                }
                .fixedSize()
                Glyph(name: "memorychip", level: (usage ?? 0) / 100, color: color, size: slot * 2.6, fromLeft: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A symbol in the secondary colour, its filled form over the share `level` (0 to 1), from the bottom or the left: a
/// level, never a full tint, so a part never looks selected by its use alone.
private struct Glyph: View {
    let name: String
    let level: Double
    let color: Color
    let size: Double
    var fromLeft = false

    var body: some View {
        let level = min(max(level, 0), 1)
        ZStack {
            Image(systemName: name).foregroundStyle(.secondary)
            Image(systemName: name + ".fill").foregroundStyle(color)
                .mask {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: fromLeft ? proxy.size.width * level : nil, height: fromLeft ? nil : proxy.size.height * level)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fromLeft ? .leading : .bottom)
                    }
                }
        }
        .font(.system(size: size))
        .accessibilityHidden(true)
    }
}

/// A GPU core as a block of lanes, filled from the bottom to `level` (0 to 1) in a light tint.
private struct GPUCore: View {
    let level: Double
    let color: Color
    let increased: Bool

    var body: some View {
        Canvas { context, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 1.5)
            let height = r.height * min(max(level, 0), 1)
            context.fill(Path(roundedRect: CGRect(x: r.minX, y: r.maxY - height, width: r.width, height: height), cornerRadius: 2),
                         with: .color(color.opacity(0.55)))
            let line = GraphicsContext.Shading.color(Color(nsColor: increased ? .labelColor : .secondaryLabelColor))
            context.stroke(Path(roundedRect: r, cornerRadius: 2), with: line, lineWidth: 1.2)
            var lanes = Path()
            for x in [r.minX + r.width / 3, r.minX + 2 * r.width / 3] { lanes.move(to: CGPoint(x: x, y: r.minY)); lanes.addLine(to: CGPoint(x: x, y: r.maxY)) }
            lanes.move(to: CGPoint(x: r.minX, y: r.midY)); lanes.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            context.stroke(lanes, with: line, lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}
