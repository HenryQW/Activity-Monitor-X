import AMXCore
import SwiftUI

/// The 3 apps whose average rose most and the 3 whose average fell most against the range of the same length before
/// it. A click on an app selects it.
struct BiggestChangesCard: View {
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    let colors: [AppKey: Color]

    var body: some View {
        let summary = history.changes.map { $0.up.isEmpty && $0.down.isEmpty ? "None" : "\($0.up.count) up, \($0.down.count) down" } ?? "No data"
        CardSection("Biggest Changes", summary: Text(summary)) {
            if let changes = history.changes {
                if changes.up.isEmpty && changes.down.isEmpty {
                    Text("No changes").foregroundStyle(.secondary)
                }
                rows("Up", changes.up)
                rows("Down", changes.down)
            } else {
                Text("No data for the range before this one").foregroundStyle(.secondary)
            }
        }
        .help("Each app's average against the range of the same length before it.")
    }

    @ViewBuilder
    private func rows(_ title: String, _ changes: [AppChange]) -> some View {
        if !changes.isEmpty {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            // By app, not `id` (its key): two names under one key are two changes.
            ForEach(changes, id: \.app) { change in
                Button { selection.app = change.app } label: {
                    LabeledContent {
                        Text((change.delta > 0 ? "+" : "-") + history.metric.format(abs(change.delta))).monospacedDigit()
                    } label: {
                        AppLabel(app: change.app, color: colors[change.app], history: history, pinned: selection.isPinned(change.app))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(change.app.name) in the inspector")
            }
        }
    }
}
