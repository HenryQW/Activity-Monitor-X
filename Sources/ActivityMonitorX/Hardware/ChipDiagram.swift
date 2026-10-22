import AMXCore
import SwiftUI

/// The chip as a schematic: one labelled grid of cores per cluster, the GPU and the memory. Neutral colours only: nothing
/// here is a state. One accessibility element, read as a sentence.
struct ChipDiagram: View {
    let chip: ChipInfo
    let gpuCores: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chip.name).font(.headline)
            HStack(alignment: .top, spacing: 14) {
                ForEach(chip.clusters, id: \.name) { cluster in
                    block(cluster.name, detail: "\(cluster.cores)") { cores(cluster.cores) }
                }
                if let gpuCores {
                    block("GPU", detail: "\(gpuCores)") { cores(gpuCores) }
                }
            }
            block("Memory", detail: memory) { EmptyView() }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.tertiary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var memory: String { Int64(chip.memory).formatted(.byteCount(style: .memory)) }

    /// "Apple M5 Pro: 5 Super cores, 10 Performance cores, 16 GPU cores, 48 GB memory"
    private var label: String {
        let parts = chip.clusters.map { "\($0.cores) \($0.name) cores" } + (gpuCores.map { ["\($0) GPU cores"] } ?? []) + ["\(memory) memory"]
        return "\(chip.name): \(parts.joined(separator: ", "))"
    }

    private func block(_ title: String, detail: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.caption)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }

    /// One small square per core, five to a row.
    private func cores(_ count: Int) -> some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<(count + 4) / 5, id: \.self) { row in
                GridRow {
                    ForEach(row * 5..<min(count, row * 5 + 5), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 9, height: 9)
                    }
                }
            }
        }
    }
}
