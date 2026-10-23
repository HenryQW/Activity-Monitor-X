import AMXCore
import SwiftUI

/// View menu: screens around the system Show/Hide Sidebar item, then the inspector.
struct GoCommands: Commands {
    let selection: Selection
    let history: HistoryModel
    let diskMap: DiskMapModel
    let alerts: AlertsModel

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("Apps") { selection.sidebar = .apps }
                .keyboardShortcut("1")
            Button("Alerts") { selection.sidebar = .alerts }
                .keyboardShortcut("2")
            Button("Disk") { selection.sidebar = .disk }
                .keyboardShortcut("3")
            Button("Hardware") { selection.sidebar = .hardware }
                .keyboardShortcut("4")
            Button("Calendar") { selection.sidebar = .calendar }
                .keyboardShortcut("5")
            Button("Energy") { selection.sidebar = .energy }
                .keyboardShortcut("6")
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Button(selection.inspectorShown ? "Hide Inspector" : "Show Inspector") {
                selection.inspectorShown.toggle()
            }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button(selection.showChart ? "Hide Chart" : "Show Chart") { selection.showChart.toggle() }
                .disabled((selection.sidebar ?? .apps) != .apps)
            Toggle("Hide Quiet System Processes", isOn: Bindable(history).hideQuietSystem)
                .disabled(selection.isSystem || selection.sidebar == .alerts)
            Button(alerts.showDismissed ? "Hide Dismissed Alerts" : "Show Dismissed Alerts") { alerts.showDismissed.toggle() }
                .disabled(selection.sidebar != .alerts)
            Button("Dismiss All Alerts") { alerts.dismiss(alerts.undismissed(search: selection.search)) }
                .disabled(selection.sidebar != .alerts || alerts.undismissed(search: selection.search).isEmpty)
            Divider()
            Button("Refresh") { selection.refreshes += 1 }
                .keyboardShortcut("r")
                .disabled(!selection.isSystem || selection.sidebar == .energy || selection.showsSpace && diskMap.target == nil)
        }
    }
}

/// File > New Group… in place of New Window: the app has one window.
struct GroupCommands: Commands {
    let selection: Selection
    let groups: GroupsModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New App Group…") { selection.editingGroup = .new }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                // While the sheet is open a new group would replace it and lose the draft.
                .disabled(groups.loadError != nil || selection.editingGroup != nil)
        }
    }
}

/// Range and Metric menus mirror the range bar and the Metric picker: System screens have no Metric (Calendar has), and only Disk's Activity pill has a Range.
struct DataCommands: Commands {
    let history: HistoryModel
    let selection: Selection

    private var noRange: Bool { selection.isSystem && selection.sidebar != .disk || selection.sidebar == .alerts || selection.showsSpace }

    var body: some Commands {
        CommandMenu("Range") {
            // One Live item: like the Live segment, it starts Live and pauses back to the range before it.
            Button(history.range == .live ? "Pause Live Data" : "Start Live Data") { history.toggleLive() }
                .keyboardShortcut("l")
                .disabled(noRange)
            Divider()
            ForEach(Array(HistoryRange.allCases.filter { $0 != .live }.enumerated()), id: \.offset) { i, range in
                Toggle(range.label, isOn: Binding(get: { history.custom == nil && history.range == range }, set: { _ in history.range = range }))
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
            }
            .disabled(noRange)
            Divider()
            Button("Custom Range…") { selection.rangeShown = true }
                .disabled(noRange)
        }
        CommandMenu("Metric") {
            ForEach(Array(history.metrics.enumerated()), id: \.offset) { i, metric in
                Toggle(metric.label, isOn: Binding(get: { history.metric == metric }, set: { _ in history.metric = metric }))
                    // Digits 1 to 9 only: a 10th metric has no shortcut.
                    .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .control]) : nil)
            }
            .disabled(selection.isSystem && selection.sidebar != .calendar || selection.sidebar == .alerts)
        }
    }
}

/// Acts on the selected app and the inspector's selected process; Quit goes through the same confirmation.
struct ProcessCommands: Commands {
    let selection: Selection

    var body: some Commands {
        CommandMenu("Process") {
            Button(selection.app.map(selection.isPinned) == true ? "Unpin App from Sidebar" : "Pin App to Sidebar") {
                selection.app.map(selection.togglePin)
            }
            // The same shortcut as the File > Add to Sidebar action.
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
