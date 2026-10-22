import Foundation

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

    /// Sizes on disk in decimal units; 0 reads "0 bytes", never "Zero KB".
    public static func bytes(_ value: Double) -> String {
        int64(value).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    /// `value` rounded, clamped to the `Int64` range; NaN is 0. `Int64(_:)` traps on these.
    public static func int64(_ value: Double) -> Int64 {
        value.isNaN ? 0 : Int64(min(max(value.rounded(), -0x1p63), 0x1p63.nextDown))
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
