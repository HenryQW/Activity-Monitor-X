import AppKit
import SwiftUI

/// History or live data does not load: the helper is not running or not installed. The raw error is in the log.
struct HelperUnavailable: View {
    @AppStorage("settingsTab") private var tab = "general"
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Cannot Load Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The helper is not running or not installed.")
        } actions: {
            Button("Open Helper Settings") {
                tab = "helper"
                // `openSettings` does not activate the app, so the window would open behind the frontmost app.
                NSApp.activate()
                openSettings()
            }
            // The screen's one action: prominent.
            .buttonStyle(.borderedProminent)
            .help("Open the helper settings")
        }
    }
}
