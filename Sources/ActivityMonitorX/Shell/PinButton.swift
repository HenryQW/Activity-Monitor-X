import AMXCore
import SwiftUI

/// Pins an app to the sidebar or unpins it, with one title, symbol and hint everywhere (D88). `short` is for the
/// inspector's action row, which has no room for the full title.
struct PinButton: View {
    let app: AppKey
    var name: String?
    let selection: Selection
    var short = false

    var body: some View {
        let pinned = selection.isPinned(app), name = name ?? app.name
        let title = short ? (pinned ? "Unpin" : "Pin") : pinned ? "Unpin App from Sidebar" : "Pin App to Sidebar"
        let action = pinned ? "Unpin \(name) from the sidebar" : "Pin \(name) to the sidebar"
        Button(title, systemImage: pinned ? "pin.slash" : "pin") { selection.togglePin(app) }
            .accessibilityLabel(action)
            .help(action)
    }
}
