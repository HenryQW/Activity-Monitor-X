import AMXCore
import SwiftUI

extension HistoryRange {
    var label: String {
        switch self {
        case .live: "Live"
        case .hour: "1H"
        case .day: "24H"
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }
}

extension Metric {
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .energy: "Energy"
        case .gpu: "GPU"
        case .score: "Score"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu, .score: (value / 100).formatted(.percent.precision(.fractionLength(1)))
        case .memory: Int64(value.rounded()).formatted(.byteCount(style: .memory))
        case .disk, .network: Metric.bytes(value) + "/s"
        case .energy: value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// Sizes on disk, as the system shows them.
    static func bytes(_ value: Double) -> String { Int64(value.rounded()).formatted(.byteCount(style: .file)) }

    /// Axis ticks carry no decimals for percentages; the bubble and tables keep `format`.
    func axisLabel(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu, .score: (value / 100).formatted(.percent.precision(.fractionLength(0)))
        default: format(value)
        }
    }
}

extension GroupColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// App colours carry meaning only: the current top-5 apps get distinct colours, every other app none. System colours
/// at least 32° of hue apart in light and dark (measured); red and yellow mean severity (`EventLane`), so they are
/// left out, and so is pink, 10° from red.
enum AppPalette {
    static let colors: [Color] = [.blue, .orange, .green, .purple, .mint]
    static let other = Color.secondary.opacity(0.35)

    /// Colours of the top apps of `points` (a stacked series), in rank order as `stacked` emits them.
    static func colors(for points: [SeriesPoint]) -> [AppKey: Color] {
        let top = points.prefix { $0.bucket == points[0].bucket }.compactMap(\.app)
        return AppColor.slots(for: top, paletteSize: colors.count).mapValues { colors[$0] }
    }
}
