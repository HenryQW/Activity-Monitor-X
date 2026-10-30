import AMXCore
import Charts
import SwiftUI

/// Live power: where the Mac's watts come from and which apps use them, then a strip with system power for the last
/// 5 min and Sort, as the Apps footer. The title pill's subtitle says the power state. Read once a second while the
/// screen shows. The search keeps the apps it matches, the rest go into Other; kept apps
/// always have a band; Sort orders the apps by watts or name. Content layer: no glass.
struct EnergyView: View {
    @Environment(LiveModel.self) private var live
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @Environment(EnergyModel.self) private var model

    var body: some View {
        content(model)
            .screenTitle("Energy", subtitle: model.power.map { Text(Self.status($0)) }, icon: .symbol("bolt"))
            .task { await model.run(client: live.client) }
    }

    @ViewBuilder private func content(_ model: EnergyModel) -> some View {
        if let power = model.power {
            let shares = model.processes.map {
                EnergyShare.top($0, query: selection.search, kept: model.kept, byName: model.sortsByName)
            } ?? []
            VStack(alignment: .leading, spacing: 0) {
                EnergyDiagram(power: power, flows: EnergyFlows(power, shares: shares, expanded: model.expanded,
                                                               processes: model.processes ?? []),
                              colors: AppPalette.colors(for: shares.compactMap(\.app), chosen: history.appColors), model: model)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if shares.isEmpty {
                            Text(model.processes == nil ? "App shares not available" : "No app uses energy now").foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                PowerStrip(model: model, top: shares.first { $0.app != nil })
                    .floatingBar()
                    .padding(Layout.inset)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "On power adapter, battery charging, 79 %".
    static func status(_ power: PowerReading) -> String {
        var parts = [power.adapterConnected ? "On power adapter" : "On battery"]
        if let battery = power.battery {
            if power.adapterConnected {
                // The measured direction first: the system can report charging while the battery also feeds the Mac.
                let watts = battery.watts ?? 0
                parts.append(watts < -0.5 ? "battery helping the adapter" : watts > 0.5 || battery.charging ? "battery charging"
                             : battery.percent == 100 ? "battery charged" : "battery not charging")
            }
            if let percent = battery.percent { parts.append(Units.percent(Double(percent))) }
        }
        return parts.joined(separator: ", ")
    }
}

/// The screen's footer (FT2): the battery as Hardware draws it (on a Mac without one, system power for the last 5 min as a
/// small line; a second without a value breaks it), then power now, the power source, the battery and the app that uses
/// the most, then Sort.
private struct PowerStrip: View {
    let model: EnergyModel
    /// The app with the largest share now.
    let top: EnergyShare?

    /// The points with a value, numbered by line segment: a missing value or a pause over 2 s starts a new one.
    private var drawn: [(date: Date, watts: Double, segment: Int)] {
        var segment = 0, previous: Date?
        return model.points.compactMap { point in
            defer { previous = point.date }
            guard let watts = point.watts else { segment += 1; return nil }
            if let previous, point.date.timeIntervalSince(previous) > 2 { segment += 1 }
            return (point.date, watts, segment)
        }
    }

    var body: some View {
        let power = model.power
        let battery = power?.battery
        var figures = [
            FooterFigure(label: "Power now", value: model.points.last?.watts.map { Units.watts($0) } ?? "No data",
                         help: "The watts this Mac uses"),
            FooterFigure(label: "Power source", value: power.map(\.sourceText) ?? "No data", help: "What powers this Mac"),
        ]
        if let battery {
            figures.append(FooterFigure(label: "Battery", value: battery.chargeText,
                                        help: "The battery charge"))
        }
        figures.append(FooterFigure(label: top.map { "Most energy, \($0.share.formatted(.percent.precision(.fractionLength(0))))" } ?? "Most energy",
                                    value: top?.app?.name ?? "None", help: "The app with the largest share of energy now"))
        return ScreenFooter(figures: figures) {
            if let battery {
                let charging = battery.charging
                BatteryShape(percent: battery.percent.map(Double.init), charging: charging,
                             level: BatteryShape.level(percent: battery.percent, charging: charging))
                    .scaleEffect(1.6)
            } else {
                chart(drawn)
            }
        } trailing: {
            CapsuleChoice(title: "Sort", values: [false, true],
                          selection: Binding(get: { model.sortsByName }, set: { if let byName = $0 { model.sortsByName = byName } })) {
                Text($0 ? "Name" : "Watts")
            }
            .help("Sort the apps by watts or by name")
        }
        .accessibilityLabel("Energy summary")
    }

    @ViewBuilder private func chart(_ drawn: [(date: Date, watts: Double, segment: Int)]) -> some View {
        let end = model.points.last?.date ?? Date()
        if drawn.isEmpty {
            Text("No data").foregroundStyle(.secondary).frame(width: 140, height: 32)
        } else {
            Chart {
                // One vectorized plot, not a mark per point.
                LinePlot(drawn, x: .value("Time", \.date), y: .value("Watts", \.watts), series: .value("Segment", \.segment))
                    .foregroundStyle(Color.accentColor)
            }
            .chartXScale(domain: end.addingTimeInterval(-300)...end)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 140, height: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("System power, last 5 minutes")
            .accessibilityValue(model.points.last?.watts.map { Units.watts($0) } ?? "No data")
            .help("System power in the last 5 minutes")
        }
    }
}
