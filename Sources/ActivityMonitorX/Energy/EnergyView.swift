import AMXCore
import Charts
import SwiftUI

/// Live power: where the Mac's watts come from and which apps use them, then system power for the last 5 min.
/// Read once a second while the screen shows. The search keeps the apps it matches, the rest go into Other; a click on
/// an app selects it for the inspector. Content layer: no glass.
struct EnergyView: View {
    @Environment(LiveModel.self) private var live
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    private let _model = State(initialValue: EnergyModel())

    var body: some View {
        let model = _model.wrappedValue
        content(model)
            .navigationTitle("Energy")
            .task { await model.run(client: live.client) }
    }

    @ViewBuilder private func content(_ model: EnergyModel) -> some View {
        if let power = model.power {
            let shares = model.processes.map { EnergyShare.top($0, query: selection.search) } ?? []
            VStack(alignment: .leading, spacing: 12) {
                EnergyDiagram(power: power, flows: EnergyFlows(power, shares: shares),
                              colors: AppPalette.colors(for: shares.compactMap(\.app), chosen: history.appColors),
                              selected: selection.app, select: { selection.app = $0 })
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if shares.isEmpty {
                            Text(model.processes == nil ? "App shares not available" : "No app uses energy now").foregroundStyle(.secondary)
                        }
                    }
                Text(Self.status(power))
                PowerChart(points: model.points)
            }
            .padding()
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

/// System power over the last 5 min in the accent colour; a second without a value breaks the line.
private struct PowerChart: View {
    let points: [EnergyModel.Point]

    /// The points with a value, numbered by line segment: a missing value or a pause over 2 s starts a new one.
    private var drawn: [(date: Date, watts: Double, segment: Int)] {
        var segment = 0, previous: Date?
        return points.compactMap { point in
            defer { previous = point.date }
            guard let watts = point.watts else { segment += 1; return nil }
            if let previous, point.date.timeIntervalSince(previous) > 2 { segment += 1 }
            return (point.date, watts, segment)
        }
    }

    var body: some View {
        let end = points.last?.date ?? Date()
        let drawn = drawn
        VStack(alignment: .leading, spacing: 6) {
            Text("System Power").font(.headline)
            if drawn.isEmpty {
                Text(points.isEmpty ? "Reading…" : "Not available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    // One vectorized plot, not a mark per point.
                    LinePlot(drawn, x: .value("Time", \.date), y: .value("Watts", \.watts), series: .value("Segment", \.segment))
                        .foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: end.addingTimeInterval(-300)...end)
                .chartXAxis { AxisMarks(preset: .aligned) }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(EnergyDiagram.watts(v, digits: 0)) }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("System power, last 5 minutes")
                .accessibilityValue(points.last?.watts.map { EnergyDiagram.watts($0) } ?? "Not available")
            }
        }
        .frame(height: 140)
    }
}
