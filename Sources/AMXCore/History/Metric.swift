public enum Metric: CaseIterable, Sendable {
    case cpu, memory, disk, network, energy, gpu

    /// Underlying process columns; the metric is their sum.
    var columns: [String] {
        switch self {
        case .cpu: ["cpu"]
        case .memory: ["mem"]
        case .disk: ["disk_r", "disk_w"]
        case .network: ["net_in", "net_out"]
        case .energy: ["energy"]
        case .gpu: ["gpu"]
        }
    }
}
