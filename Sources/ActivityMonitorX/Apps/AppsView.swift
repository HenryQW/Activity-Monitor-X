import AMXCore
import Charts
import SwiftUI

/// Every app seen in the range with its average, peak and sparkline; pin or unpin from the row button or the context menu.
struct AppsView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    private let _sortOrder = State(initialValue: [KeyPathComparator(\Row.average, order: .reverse)])

    var body: some View {
        let isLive = history.range == .live
        let all = isLive ? live.ranking : history.apps
        let shown = AppSearch.filter(all, query: selection.search)
        Group {
            switch isLive ? live.state : history.state {
            case .loading:
                ProgressView()
            case .empty:
                ContentUnavailableView("Collecting data…", systemImage: "clock")
            case .failed:
                HelperUnavailable()
            case .ready:
                table(apps: shown, sparklines: isLive ? live.sparklines : history.sparklines)
            }
        }
        .navigationTitle("Apps")
        .navigationSubtitle(selection.subtitle(history.subtitle, shown: shown.count, of: all.count))
        .onAppear { live.sparklinesShown = true }
        .onDisappear { live.sparklinesShown = false }
    }

    private func table(apps: [AppRank], sparklines: [AppKey: [Double]]) -> some View {
        let rows = apps.map { Row(app: $0.app, name: $0.app.name, average: $0.average, peak: $0.peak) }
            .sorted(using: _sortOrder.wrappedValue)
        let metric = history.metric
        let colors = AppPalette.colors(for: history.range == .live ? live.stacked : history.stacked)
        let details = AppKey.details(for: apps.map(\.app))
        // One y scale per metric: 0 to the largest value in view, so rows compare with each other.
        let top = apps.compactMap { sparklines[$0.app]?.max() }.max() ?? 1

        return Table(rows, selection: Bindable(selection).app, sortOrder: _sortOrder.projectedValue) {
            TableColumn("App", value: \.name) { AppLabel(app: $0.app, color: colors[$0.app], pinned: selection.isPinned($0.app), detail: details[$0.app.key]) }
                .width(min: 140)
            TableColumn("Average", value: \.average) { Text(metric.format($0.average)).monospacedDigit() }
                .width(min: 80, ideal: 88, max: 110)
                .alignment(.trailing)
            TableColumn("Peak", value: \.peak) { Text(metric.format($0.peak)).monospacedDigit() }
                .width(min: 80, ideal: 88, max: 110)
                .alignment(.trailing)
            TableColumn("Trend") { row in
                Sparkline(values: sparklines[row.app] ?? [], color: colors[row.app] ?? .secondary, top: top)
            }
            .width(min: 60, ideal: 80, max: 120)
            TableColumn("") { row in
                pinButton(row.app).labelStyle(.iconOnly).buttonStyle(.borderless)
                    .accessibilityLabel(selection.isPinned(row.app) ? "Unpin \(row.name)" : "Pin \(row.name)")
            }
                .width(28)
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

/// One line, no axes; the y scale is shared by every row (0 to `top`).
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let top: Double

    var body: some View {
        Chart {
            ForEach(values.indices, id: \.self) { i in
                LineMark(x: .value("Time", i), y: .value("Value", values[i]))
            }
        }
        .foregroundStyle(color)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(top, .leastNonzeroMagnitude))
        .chartLegend(.hidden)
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
