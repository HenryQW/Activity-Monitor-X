import AMXCore
import SwiftUI

/// The selected Calendar cell: its time, its value and its top apps (those the search matches), with Show in Apps.
struct CalendarInspector: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    /// The cell's apps as last read; nil after a failed read.
    private let _apps = State<[AppRank]?>(initialValue: nil)
    private let _reading = State(initialValue: true)

    private struct Read: Equatable {
        let start: Double
        let metric: Metric
        let query: String
    }

    var body: some View {
        if let page = model.page, let cell = model.selectedCell, let value = cell.value {
            Form {
                Section { Text(cell.time(page.period)).font(.title3.bold()) }
                Section(page.query.isEmpty ? "Total" : "Total of Matching Apps") {
                    Text(page.metric.format(value)).monospacedDigit()
                }
                Section("Top Apps") {
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
                    Button("Show in Apps") { selection.reveal(from: cell.start, to: cell.end, history: history) }
                        .help("Open Apps at this time")
                }
            }
            .formStyle(.grouped)
            .task(id: Read(start: cell.start, metric: page.metric, query: page.query)) {
                _reading.wrappedValue = true
                let apps = await model.apps(in: cell, metric: page.metric, query: page.query)
                // A newer cell's read owns the card.
                guard !Task.isCancelled else { return }
                (_apps.wrappedValue, _reading.wrappedValue) = (apps, false)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "calendar",
                                   description: Text("Click an hour or a day to see its top apps."))
        }
    }
}
