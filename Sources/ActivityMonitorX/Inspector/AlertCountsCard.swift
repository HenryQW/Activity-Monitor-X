import AMXCore
import SwiftUI

/// The range's warnings and critical events counted by rule, most first, and a way to the Alerts screen.
struct AlertCountsCard: View {
    @Environment(Selection.self) private var selection
    let events: [EventMark]

    var body: some View {
        let counts = Dictionary(grouping: events) { $0.rule ?? $0.kind }
            .map { (rule: $0.key, count: $0.value.count) }
            .sorted { ($1.count, $0.rule) < ($0.count, $1.rule) }
        CardSection("Alerts", summary: Text(events.count.formatted())) {
            if counts.isEmpty {
                Text("No alerts").foregroundStyle(.secondary)
            }
            ForEach(counts, id: \.rule) { LabeledContent(RuleName.title($0.rule), value: $0.count.formatted()).monospacedDigit() }
            Button("Show in Alerts") { selection.sidebar = .alerts }
                .help("Open the Alerts screen")
        }
    }
}
