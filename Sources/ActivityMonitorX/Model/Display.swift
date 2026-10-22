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
        case .memory: Metric.int64(value).formatted(.byteCount(style: .memory))
        case .disk, .network: Metric.bytes(value) + "/s"
        case .energy: value.formatted(.number.precision(.fractionLength(1)))
        }
    }

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

/// App colours carry meaning only: the current top-5 apps get distinct colours, apps with a colour the user chose get
/// that one, every other app none. System colours at least 32° of hue apart in light and dark (measured); red and
/// yellow mean severity (`EventLane`), so they are left out, and so is pink, 10° from red.
enum AppPalette {
    static let colors: [Color] = [.blue, .orange, .green, .purple, .mint]
    /// What the user can choose for an app: the palette and a few more system colours, none near red or yellow.
    static let choices: [GroupColor] = [.blue, .orange, .green, .purple, .mint, .teal, .cyan, .indigo, .brown]
    static let other = Color.secondary.opacity(0.35)
    /// Reserved for hover: the line of a hovered app that has no colour of its own. Never an app's colour.
    static let hover = Color.primary

    /// Each app's first slot, read once and saved when an app is added, so it keeps its colour across views, metrics
    /// and launches.
    @MainActor private static var stored = UserDefaults.standard.data(forKey: "appColorSlots")
        .flatMap { try? JSONDecoder().decode(StoredSlots.self, from: $0) } ?? StoredSlots() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: "appColorSlots") }
    }

    /// Colours of the apps of `points` (a stacked series), in rank order as `stacked` emits them: a `chosen` colour
    /// (by app key) wins, the others get palette slots. An app past the palette (its colour was just cleared, until the
    /// next load) draws as Other.
    @MainActor static func colors(for points: [SeriesPoint], chosen: [String: GroupColor]) -> [AppKey: Color] {
        colors(for: points.prefix { $0.bucket == points[0].bucket }.compactMap(\.app), chosen: chosen)
    }

    /// Colours of the `named` apps, in rank order, as for a stacked series.
    @MainActor static func colors(for named: [AppKey], chosen: [String: GroupColor]) -> [AppKey: Color] {
        let top = named.filter { chosen[$0.key] == nil }.prefix(colors.count)
        var slots = stored
        let result = AppColor.slots(for: Array(top), paletteSize: colors.count, stored: &slots)
        if slots != stored { stored = slots }
        return Dictionary(uniqueKeysWithValues: named.map { app in
            (app, chosen[app.key]?.color ?? result[app].map { colors[$0] } ?? other)
        })
    }
}
