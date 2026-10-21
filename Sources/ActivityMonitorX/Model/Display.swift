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

    var subtitle: String {
        switch self {
        case .live: "Live"
        case .hour: "Last Hour"
        case .day: "Last 24 Hours"
        case .week: "Last 7 Days"
        case .month: "Last 30 Days"
        case .quarter: "Last 90 Days"
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
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu: (value / 100).formatted(.percent.precision(.fractionLength(1)))
        case .memory: Int64(value.rounded()).formatted(.byteCount(style: .memory))
        case .disk, .network: Int64(value.rounded()).formatted(.byteCount(style: .file)) + "/s"
        case .energy: value.formatted(.number.precision(.fractionLength(1)))
        }
    }
}

/// App colours carry meaning only: the current top-5 apps get distinct colours, every other app none.
enum AppPalette {
    static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .red, .indigo, .mint]
    static let other = Color.secondary.opacity(0.35)

    /// Colours of the top apps of `points` (a stacked series), in rank order as `stacked` emits them.
    static func colors(for points: [SeriesPoint]) -> [AppKey: Color] {
        let top = points.prefix { $0.bucket == points[0].bucket }.compactMap(\.app)
        return AppColor.slots(for: top, paletteSize: colors.count).mapValues { colors[$0] }
    }
}
