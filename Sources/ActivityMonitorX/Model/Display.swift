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

/// One format per quantity, used on every screen (D88). Each is the system format, so it follows the locale.
enum Units {
    /// Whole percents of 0 to 100: "42%".
    static func percent(_ value: Double) -> String { (value / 100).formatted(.percent.precision(.fractionLength(0))) }
    static func watts(_ value: Double, digits: Int = 1) -> String { measure(value, UnitPower.watts, digits) }
    /// Whole degrees as read, never converted: "47°C".
    static func celsius(_ value: Double) -> String { measure(value, UnitTemperature.celsius, 0) }
    /// Disk latency: "0.2 ms".
    static func milliseconds(_ value: Double) -> String { measure(value, UnitDuration.milliseconds, 1) }
    /// Disk operations: "120/s".
    static func perSecond(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) + "/s" }
    /// Uptime: "2 days, 3 hr".
    static func uptime(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    private static func measure<U: Dimension>(_ value: Double, _ unit: U, _ digits: Int) -> String {
        Measurement(value: value, unit: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))))
    }
}

extension PowerReading {
    /// "Adapter, 96 W" or "Battery": short, so it fits a footer column.
    var sourceText: String { adapterConnected ? "Adapter" + (adapterRating.map { ", " + Units.watts($0, digits: 0) } ?? "") : "Battery" }
}

extension PowerReading.Battery {
    /// "79%, charging"; "No data" with no reading.
    var chargeText: String { (percent.map { Units.percent(Double($0)) } ?? "No data") + (charging ? ", charging" : "") }
}

extension GroupColor {
    var color: Color {
        switch self {
        case .orange: .orange
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .brown: .brown
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
