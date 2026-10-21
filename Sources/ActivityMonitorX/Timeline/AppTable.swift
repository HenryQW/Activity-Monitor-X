import AMXCore
import SwiftUI

/// Apps ranked for the span (or the whole range), each expandable to its processes.
struct AppTable: View {
    let ranking: [AppRank]
    /// The chart's top apps; other apps get no dot.
    let colors: [AppKey: Color]
    let metric: Metric

    @Environment(Selection.self) private var selection
    private let _selected = State<Row.ID?>(initialValue: nil)
    private let _sortOrder = State(initialValue: [KeyPathComparator(\Row.average, order: .reverse)])

    var body: some View {
        let sortOrder = _sortOrder.wrappedValue
        let rows = ranking.map { app in
            Row(id: app.app.key, name: app.app.name, app: app.app, process: nil, average: app.average, peak: app.peak,
                processes: Self.processRows(app).sorted(using: sortOrder))
        }.sorted(using: sortOrder)
        let byID = Dictionary(uniqueKeysWithValues: rows.flatMap { [$0] + $0.processes }.map { ($0.id, $0) })
        let selected = Binding<Row.ID?>(
            get: {
                // A process row stays selected only while `selection.process` holds it (Quit clears it).
                let processRowLostSelection = _selected.wrappedValue.flatMap { byID[$0] }?.process != nil
                    && selection.process == nil
                return processRowLostSelection ? nil : _selected.wrappedValue
            },
            set: { id in
                _selected.wrappedValue = id
                let row = id.flatMap { byID[$0] }
                // App first: changing the app clears the process.
                selection.app = row?.app
                selection.process = row?.process
            })

        Table(of: Row.self, selection: selected, sortOrder: _sortOrder.projectedValue) {
            TableColumn("App", value: \.name) { row in
                if let process = row.process {
                    HStack {
                        Text("\(row.name) (\(String(process.pid)))")
                        if process.exited {
                            Spacer()
                            Text("Exited").font(.caption)
                        }
                    }
                    .foregroundStyle(process.exited ? .tertiary : .secondary)
                } else {
                    Label {
                        Text(row.name).help(row.app.key)
                    } icon: {
                        Circle().fill(colors[row.app] ?? .clear).frame(width: 8, height: 8)
                    }
                }
            }
            TableColumn("Average", value: \.average) { Text(metric.format($0.average)).monospacedDigit() }
                .alignment(.trailing)
            TableColumn("Peak", value: \.peak) { Text(metric.format($0.peak)).monospacedDigit() }
                .alignment(.trailing)
        } rows: {
            ForEach(rows) { app in
                DisclosureTableRow(app) {
                    ForEach(app.processes) { TableRow($0) }
                }
            }
        }
    }

    /// Live rows have no DB id (processID 0) and a pid can repeat inside the Live window, so a repeat
    /// gets its occurrence number; other ids stay stable across reloads.
    private static func processRows(_ app: AppRank) -> [Row] {
        var seen: [String: Int] = [:]
        return app.processes.map { p in
            let base = "\(app.app.key)/\(p.processID)/\(p.pid)"
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return Row(id: n == 1 ? base : "\(base)#\(n)", name: p.name, app: app.app, process: p,
                       average: p.average, peak: p.peak, processes: [])
        }
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let app: AppKey
        /// nil for an app row.
        let process: ProcessRank?
        let average: Double
        let peak: Double
        let processes: [Row]
    }
}
