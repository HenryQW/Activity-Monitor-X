public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, disk, network, energy, gpu, score

    /// The metrics stored per process; `score` is blended from them at read time.
    public static let recorded: [Metric] = allCases.filter { $0 != .score }

    /// Underlying process columns; the metric is their sum.
    var columns: [String] {
        switch self {
        case .cpu: ["cpu"]
        case .memory: ["mem"]
        case .disk: ["disk_r", "disk_w"]
        case .network: ["net_in", "net_out"]
        case .energy: ["energy"]
        case .gpu: ["gpu"]
        case .score: ["cpu", "mem"]
        }
    }
}
