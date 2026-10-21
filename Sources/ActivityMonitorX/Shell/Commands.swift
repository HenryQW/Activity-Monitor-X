import AMXCore
import SwiftUI

struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarItem?>
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarItem?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }
}

/// View menu: screens around the system Show/Hide Sidebar item, then the inspector.
struct GoCommands: Commands {
    let selection: Selection
    let history: HistoryModel
    @FocusedValue(\.sidebarSelection) private var sidebar

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("Timeline") { sidebar?.wrappedValue = .timeline }
                .keyboardShortcut("1")
            Button("Apps") { sidebar?.wrappedValue = .apps }
                .keyboardShortcut("2")
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Button(selection.inspectorShown ? "Hide Inspector" : "Show Inspector") { selection.inspectorShown.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Hide Quiet System Processes", isOn: Bindable(history).hideQuietSystem)
        }
    }
}

/// Range and Metric menus mirror the toolbar pickers.
struct DataCommands: Commands {
    let history: HistoryModel

    var body: some Commands {
        CommandMenu("Range") {
            ForEach(Array(HistoryRange.allCases.enumerated()), id: \.offset) { i, range in
                Toggle(range.label, isOn: Binding(get: { history.range == range }, set: { _ in history.range = range }))
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: i == 0 ? .command : [.command, .option])
            }
        }
        CommandMenu("Metric") {
            ForEach(Array(Metric.recorded.enumerated()), id: \.offset) { i, metric in
                Toggle(metric.label, isOn: Binding(get: { history.metric == metric }, set: { _ in history.metric = metric }))
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .control])
            }
        }
    }
}

/// Acts on the selected app and the inspector's selected process; Quit goes through the same confirmation.
struct ProcessCommands: Commands {
    let selection: Selection

    var body: some Commands {
        CommandMenu("Process") {
            Button(selection.app.map(selection.isPinned) == true ? "Unpin App" : "Pin App") {
                selection.app.map(selection.togglePin)
            }
            // The usual shortcut for Add to Sidebar.
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(selection.app == nil)
            Divider()
            Button("Quit Process…") { request(SIGTERM) }
                .keyboardShortcut("q", modifiers: [.command, .option])
                .disabled(selection.signallable == nil)
            Button("Force Quit Process…") { request(SIGKILL) }
                .disabled(selection.signallable == nil)
        }
    }

    private func request(_ signal: Int32) {
        selection.signalRequest = selection.signallable.map { SignalRequest(process: $0, signal: signal) }
    }
}
