import AMXCore
import SwiftUI

/// The chip as a schematic: one labelled grid of cores per cluster, the GPU and the memory. A core square is grey and
/// takes the accent colour as its usage rises (no warning colours: nothing here is a state). Each group is one
/// accessibility element with its usage as the value.
struct ChipDiagram: View {
    let chip: ChipInfo
    let gpuCores: Int?
    /// Per logical CPU; empty until the second read.
    let cpuUsage: [Double]
    /// Nil until the first read.
    let gpuUsage: Double?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(chip.name).font(.headline)
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow(alignment: .top) {
                        ForEach(chip.clusters.indices, id: \.self) { index in cluster(index) }
                        if let gpuCores { gpu(gpuCores) }
                    }
                    GridRow {
                        block("Memory", detail: memory, label: "Memory, \(memory)", value: nil) { EmptyView() }
                            .gridCellColumns(chip.clusters.count + (gpuCores == nil ? 0 : 1))
                    }
                }
                Text("Shade shows current use").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chip.name)
    }

    private var memory: String { Int64(chip.memory).formatted(.byteCount(style: .memory)) }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    private func cluster(_ index: Int) -> some View {
        let cluster = chip.clusters[index]
        // Usage is shown only when the read covers every core of the chip.
        let usage = cpuUsage.count == chip.clusters.reduce(0) { $0 + $1.cores } ? Array(cpuUsage[chip.cpuIndexes(cluster: index)]) : []
        let average = usage.isEmpty ? nil : usage.reduce(0, +) / Double(usage.count)
        return block(cluster.name, detail: "\(cluster.cores)", label: "\(cluster.name), \(cluster.cores) cores",
                     value: average.map { "\(Self.percent($0)) busy" }) {
            cores(cluster.cores) { i in
                let name = "\(cluster.name) core \(i + 1)"
                return usage.isEmpty ? (0, name) : (usage[i], "\(name): \(Self.percent(usage[i]))")
            }
        }
    }

    /// macOS gives no per-core GPU use: the lit squares follow the total, 40 % of 16 lights 6.
    private func gpu(_ count: Int) -> some View {
        let lit = Int((Double(count) * (gpuUsage ?? 0) / 100).rounded())
        let hint = gpuUsage.map { "GPU \(Self.percent($0))" } ?? "GPU"
        return block("GPU", detail: "\(count)", label: "GPU, \(count) cores", value: gpuUsage.map { "\(Self.percent($0)) busy" }) {
            cores(count) { i in (i < lit ? 100 : 0, hint) }
        }
    }

    private func block(_ title: String, detail: String, label: String, value: String?,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stacked, so a long cluster name ("Performance") never truncates.
            VStack(alignment: .leading, spacing: 0) {
                Text(title).lineLimit(1).fixedSize()
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.caption)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }

    /// One small square per core, five to a row: grey, with the accent colour over it at the core's usage (0-100) and its hint.
    private func cores(_ count: Int, square: @escaping (Int) -> (usage: Double, hint: String)) -> some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<(count + 4) / 5, id: \.self) { row in
                GridRow {
                    ForEach(row * 5..<min(count, row * 5 + 5), id: \.self) { i in
                        let (usage, hint) = square(i)
                        RoundedRectangle(cornerRadius: 2).fill(.secondary)
                            .overlay(RoundedRectangle(cornerRadius: 2).fill(.tint.opacity(usage / 100)))
                            .frame(width: 9, height: 9)
                            .help(hint)
                    }
                }
            }
        }
    }
}
