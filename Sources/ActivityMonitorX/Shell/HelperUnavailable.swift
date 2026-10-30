import AppKit
import ServiceManagement
import SwiftUI

/// History or live data does not load: the helper is not running, not installed, or waits for approval in Login
/// Items (D91). The raw error is in the log.
struct HelperUnavailable: View {
    @AppStorage("settingsTab") private var tab = "general"
    @Environment(\.openSettings) private var openSettings
    @Environment(HelperService.self) private var helper

    var body: some View {
        ContentUnavailableView {
            Label("Cannot Load Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(helper.needsApproval
                 ? "The helper waits for your approval. Turn on Activity Monitor X in Login Items to start the recording."
                 : "The helper is not running or not installed.")
        } actions: {
            Group {
                if helper.needsApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                        .help("Open Login Items in System Settings to allow the helper to run")
                } else {
                    Button("Open Helper Settings") {
                        tab = "helper"
                        // `openSettings` does not activate the app, so the window would open behind the frontmost app.
                        NSApp.activate()
                        openSettings()
                    }
                    .help("Open the helper settings")
                }
            }
            // The screen's one action: prominent.
            .buttonStyle(.borderedProminent)
        }
    }
}
