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
    private let _model = State(initialValue: EnergyModel())

    var body: some View {
        let model = _model.wrappedValue
        content(model)
            .screenTitle("Energy", subtitle: model.power.map { Text(Self.status($0)) }, icon: .symbol("bolt.fill"))
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
                PowerStrip(model: model)
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
            if let percent = battery.percent { parts.append((Double(percent) / 100).formatted(.percent)) }
        }
        return parts.joined(separator: ", ")
    }
}

/// One strip under the flow, as the Apps footer: system power for the last 5 min as a small line with no title, now,
/// the average and the peak, then Sort. A second without a value breaks the line.
private struct PowerStrip: View {
    let model: EnergyModel

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
        let drawn = drawn
        let watts = drawn.map(\.watts)
        let figures = HStack(alignment: .top, spacing: 18) {
            Figure(label: "Now") { Text(model.points.last?.watts.map { EnergyDiagram.watts($0) } ?? "Not available") }
            // The points start when the screen opens, so the window is up to 5 min: the hint says so, not the label.
            Figure(label: "Average") { Text(watts.isEmpty ? "No data" : EnergyDiagram.watts(watts.reduce(0, +) / Double(watts.count))) }
                .help("The average since the screen opened, up to the last 5 minutes")
            Figure(label: "Peak") { Text(watts.max().map { EnergyDiagram.watts($0) } ?? "No data") }
                .help("The highest value since the screen opened, up to the last 5 minutes")
        }
        let sort = CapsuleChoice(title: "Sort", values: [false, true],
                                 selection: Binding(get: { model.sortsByName }, set: { if let byName = $0 { model.sortsByName = byName } })) {
            Text($0 ? "Name" : "Watts")
        }
        .help("Sort the apps by watts or by name")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                chart(drawn)
                Divider().frame(height: 30)
                figures
                Spacer(minLength: 0)
                sort
            }
            HStack(spacing: 18) {
                figures
                Spacer(minLength: 0)
                sort
            }
        }
        .padding(Layout.padding)
    }

    @ViewBuilder private func chart(_ drawn: [(date: Date, watts: Double, segment: Int)]) -> some View {
        let end = model.points.last?.date ?? Date()
        if drawn.isEmpty {
            Text(model.points.isEmpty ? "Reading…" : "Not available").foregroundStyle(.secondary).frame(width: 140, height: 32)
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
            .accessibilityValue(model.points.last?.watts.map { EnergyDiagram.watts($0) } ?? "Not available")
            .help("System power in the last 5 minutes")
        }
    }
}
