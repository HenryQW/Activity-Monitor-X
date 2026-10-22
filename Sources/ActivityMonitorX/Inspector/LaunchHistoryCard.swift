import AMXCore
import SwiftUI

/// When the app's processes started and quit in the range (or span), newest first: 10 rows, then Show All.
struct LaunchHistoryCard: View {
    @Environment(HistoryModel.self) private var history
    let app: AppKey
    /// The app whose full list is shown; another app starts short again.
    private let _showAllOf = State<String?>(initialValue: nil)

    var body: some View {
        let launches = history.launches(of: app)
        let shown = launches.prefix(_showAllOf.wrappedValue == app.key ? .max : 10)
        let format: Date.FormatStyle = history.range.seconds >= 86_400
            ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute()
        InspectorCard(title: "Launch History") {
            if launches.isEmpty {
                Text("No process started or quit in this range").foregroundStyle(.secondary)
            }
            ForEach(shown) { event in
                LabeledContent("\(event.isQuit ? "Quit" : "Started") \(event.name) (\(String(event.pid)))",
                               value: Date(timeIntervalSince1970: event.ts).formatted(format))
                    .monospacedDigit()
            }
            if shown.count < launches.count {
                Button("Show All \(launches.count.formatted())") { _showAllOf.wrappedValue = app.key }
                    .buttonStyle(.link)
                    .help("Show all process starts and quits")
            }
        }
    }
}
