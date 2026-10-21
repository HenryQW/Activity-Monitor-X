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

    /// Names the start when recording began inside the range.
    func subtitle(since: Double?) -> String {
        guard let since else { return subtitle }
        let date = Date(timeIntervalSince1970: since).formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "\(subtitle), since \(date)"
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
        case .disk, .network: Int64(value.rounded()).formatted(.byteCount(style: .file)) + "/s"
        case .energy: value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// Axis ticks carry no decimals for percentages; the bubble and tables keep `format`.
    func axisLabel(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu: (value / 100).formatted(.percent.precision(.fractionLength(0)))
        default: format(value)
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
