import AMXCore
import Charts
import SwiftUI

/// Every app seen in the range with its average, peak and sparkline; pin or unpin from here.
struct AppsView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    private let _sortOrder = State(initialValue: [KeyPathComparator(\Row.average, order: .reverse)])

    var body: some View {
        let isLive = history.range == .live
        Group {
            switch isLive ? live.state : history.state {
            case .loading:
                ProgressView()
            case .empty:
                ContentUnavailableView("Collecting data…", systemImage: "clock")
            case .failed(let message):
                ContentUnavailableView("Cannot Load Data", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                table(apps: isLive ? live.ranking : history.apps, sparklines: isLive ? live.sparklines : history.sparklines)
            }
        }
        .navigationTitle("Apps")
        .navigationSubtitle(history.range.subtitle)
        .onAppear { live.sparklinesShown = true }
        .onDisappear { live.sparklinesShown = false }
    }

    private func table(apps: [AppRank], sparklines: [AppKey: [Double]]) -> some View {
        let rows = apps.map { Row(app: $0.app, name: $0.app.name, average: $0.average, peak: $0.peak) }
            .sorted(using: _sortOrder.wrappedValue)
        let metric = history.metric
        let colors = AppPalette.colors(for: history.range == .live ? live.stacked : history.stacked)

        return Table(rows, selection: Bindable(selection).app, sortOrder: _sortOrder.projectedValue) {
            TableColumn("App", value: \.name) { row in
                Label {
                    Text(row.name).help(row.app.key)
                } icon: {
                    Circle().fill(colors[row.app] ?? .clear).frame(width: 8, height: 8)
                }
            }
            .width(min: 100, ideal: 180)
            TableColumn("Average", value: \.average) { Text(metric.format($0.average)).monospacedDigit() }
                .width(min: 60, ideal: 80)
                .alignment(.trailing)
            TableColumn("Peak", value: \.peak) { Text(metric.format($0.peak)).monospacedDigit() }
                .width(min: 60, ideal: 80)
                .alignment(.trailing)
            TableColumn("Trend") { row in
                Sparkline(values: sparklines[row.app] ?? [], color: colors[row.app] ?? .secondary)
            }
            .width(min: 50, ideal: 90, max: 140)
            TableColumn("Pin") { row in
                pinButton(row.app)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .width(32)
        }
        .contextMenu(forSelectionType: AppKey.self) { apps in
            if let app = apps.first { pinButton(app) }
        }
    }

    private func pinButton(_ app: AppKey) -> some View {
        let pinned = selection.isPinned(app)
        return Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.fill" : "pin") { selection.togglePin(app) }
            .help(pinned ? "Unpin \(app.name)" : "Pin \(app.name) to the sidebar")
    }

    struct Row: Identifiable {
        var id: AppKey { app }
        let app: AppKey
        let name: String
        let average: Double
        let peak: Double
    }
}

/// One line, no axes; the y scale is the row's own.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(values.indices, id: \.self) { i in
                LineMark(x: .value("Time", i), y: .value("Value", values[i]))
            }
        }
        .foregroundStyle(color)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
