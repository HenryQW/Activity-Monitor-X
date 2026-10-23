import AMXCore
import AppKit
import SwiftUI

/// A Pinned Apps row: the name (its hint gives the full name when the sidebar truncates it), a `pin.slash` button on hover
/// that unpins at once, and the right-click menu of the app's actions.
struct PinnedRow: View {
    let app: AppKey
    let history: HistoryModel
    let selection: Selection
    /// The app whose Alert Rules sheet `MainWindow` shows.
    @Binding var rulesApp: AppKey?
    private let _hover = State(initialValue: false)

    var body: some View {
        let name = AppName.display(app, history: history)
        HStack(spacing: 0) {
            Label(name, systemImage: "pin").help(name)
            Spacer(minLength: 0)
            if _hover.wrappedValue {
                Button("Unpin \(name)", systemImage: "pin.slash") { selection.togglePin(app) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Unpin \(name) from the sidebar")
            }
        }
        .onHover { _hover.wrappedValue = $0 }
        .contextMenu {
            Group {
                Button("Show in Inspector", systemImage: "sidebar.trailing") {
                    selection.sidebar = .pinned(app)
                    selection.app = app
                    selection.inspectorShown = true
                }
                .help("Show \(name) in the inspector")
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: app.key)])
                }
                // A bare executable name has no path to show.
                .disabled(!app.key.hasPrefix("/"))
                .help(app.key.hasPrefix("/") ? "Show \(name) in the Finder" : "\(name) has no app bundle to show")
                Menu("Colour", systemImage: "paintpalette") { AppColorPicker(app: app, history: history) }
                    .help("Choose the colour that shows \(name)")
                Button("Alert Rules…", systemImage: "bell") { rulesApp = app }
                    .help("Mute alerts for \(name) or give it its own alert values")
                Divider()
                Button("Unpin App from Sidebar", systemImage: "pin.slash") { selection.togglePin(app) }
                    .help("Unpin \(name) from the sidebar")
                let running = InspectorView.running(app)
                Button("Quit…", systemImage: "xmark.circle") {
                    selection.signalRequest = SignalRequest(app: name, running: running, signal: SIGTERM)
                }
                .disabled(running.isEmpty)
                .help(running.isEmpty ? "No running processes" : "Quit \(name), or force quit it")
            }
                .labelStyle(.titleAndIcon)
        }
    }
}
