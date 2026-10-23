import AMXCore
import SwiftUI

/// The selected Calendar cell: its time, its value and its top apps (those the search matches), with Show in Apps. With
/// no cell selected, the period at a glance: its average, its busiest hour or day, its alert count and its top apps.
struct CalendarInspector: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    /// The cell's (or the period's) apps as last read; nil after a failed read.
    private let _apps = State<[AppRank]?>(initialValue: nil)
    private let _reading = State(initialValue: true)
    /// The alerts of the period as last read; nil after a failed read.
    private let _alerts = State<Int?>(initialValue: nil)

    private struct Read: Equatable {
        let start: Double
        let end: Double
        let metric: Metric
        let query: String
    }

    var body: some View {
        if let page = model.page {
            // A cell without data shows the period.
            let cell = model.selectedCell.flatMap { $0.value == nil ? nil : $0 }
            let (start, end) = cell.map { ($0.start, $0.end) }
                ?? (page.interval.start.timeIntervalSince1970, page.interval.end.timeIntervalSince1970)
            Form {
                if let cell, let value = cell.value {
                    Section { Text(cell.time(page.period)).font(.title3.bold()) }
                    Section(page.query.isEmpty ? "Total" : "Total of Matching Apps") {
                        Text(page.metric.format(value)).monospacedDigit()
                    }
                } else {
                    summary(page)
                }
                Section {
                    if _reading.wrappedValue {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let apps = _apps.wrappedValue {
                        if apps.isEmpty { Text("No apps").foregroundStyle(.secondary) }
                        ForEach(apps.prefix(5)) { rank in
                            LabeledContent(rank.app.name, value: page.metric.format(rank.average)).monospacedDigit()
                        }
                    } else {
                        Text("Cannot read the history").foregroundStyle(.secondary)
                    }
                    if let cell {
                        Button("Show in Apps") { selection.reveal(from: cell.start, to: cell.end, history: history) }
                            .help("Open Apps at this time")
                    }
                } header: {
                    Text("Top Apps")
                } footer: {
                    if cell == nil { Text(page.period == .month ? "Click a day to see its top apps." : "Click an hour to see its top apps.") }
                }
            }
            .formStyle(.grouped)
            .task(id: Read(start: start, end: end, metric: page.metric, query: page.query)) {
                _reading.wrappedValue = true
                let apps = await model.apps(from: start, to: end, metric: page.metric, query: page.query)
                let alerts = await model.alertCount(from: start, to: end)
                // A newer read owns the card.
                guard !Task.isCancelled else { return }
                (_apps.wrappedValue, _alerts.wrappedValue, _reading.wrappedValue) = (apps, alerts, false)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "calendar",
                                   description: Text("Click an hour or a day to see its top apps."))
        }
    }

    /// The period's mean of its cells with data, its busiest cell (a click selects it) and its alerts.
    @ViewBuilder private func summary(_ page: CalendarPage) -> some View {
        let cells = page.grid.joined().compactMap { $0 }.filter { $0.value != nil }
        let busiest = cells.max { $0.value! < $1.value! }
        let unit = page.period == .month ? "Day" : "Hour"
        Section { Text("\(page.period.rawValue.capitalized) Summary").font(.title3.bold()) }
        Section(page.metric.label) {
            LabeledContent("Average", value: cells.isEmpty ? "No data"
                           : page.metric.format(cells.reduce(0) { $0 + $1.value! } / Double(cells.count)))
            if let busiest {
                Button { model.selected = busiest.start } label: {
                    LabeledContent("Busiest \(unit.lowercased())", value: Date(timeIntervalSince1970: busiest.start)
                        .formatted(page.period == .month ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                   : .dateTime.weekday(.abbreviated).day().hour()))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select the busiest \(unit.lowercased())")
            }
            LabeledContent("Alerts", value: _alerts.wrappedValue?.formatted() ?? "No data")
                .help("The alerts in this \(page.period.rawValue)")
        }
        .monospacedDigit()
    }
}
