public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, disk, network, energy, gpu, score

    /// The metrics stored per process; `score` is blended from them at read time.
    public static let recorded: [Metric] = allCases.filter { $0 != .score }

    public var unit: String {
        switch self {
        case .cpu: "% of one core"
        case .memory: "bytes"
        case .disk, .network: "bytes/s"
        case .energy: "energy impact"
        case .gpu: "% GPU"
        case .score: "% of this Mac, 0 to 100 (0.5 x cpu/cores + 50 x mem/memory)"
        }
    }

    /// Underlying process columns; the metric is their sum.
    var columns: [String] {
        switch self {
        case .cpu: ["cpu"]
        case .memory: ["mem"]
        case .disk: ["disk_r", "disk_w"]
        case .network: ["net_in", "net_out"]
        case .energy: ["energy"]
        case .gpu: ["gpu"]
        case .score: ["cpu", "mem"] // Not read: HistoryReader weighs these two itself; listed for the exhaustive switch.
        }
    }
}
