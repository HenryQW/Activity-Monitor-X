import AMXCore
import SwiftUI

/// View menu: screens around the system Show/Hide Sidebar item, then the inspector.
struct GoCommands: Commands {
    let selection: Selection
    let history: HistoryModel
    let diskMap: DiskMapModel
    let alerts: AlertsModel
    let calendar: CalendarModel

    /// The screens with a zoom pill: Apps (with the chart shown), pinned apps and groups, and Disk's Activity.
    private var chartZoom: Bool { selection.hasRange && ((selection.sidebar ?? .apps) != .apps || selection.showChart) }

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Group {
                Button("Apps", systemImage: "square.grid.2x2") { selection.sidebar = .apps }
                    .keyboardShortcut("1")
                Button("Alerts", systemImage: "exclamationmark.triangle") { selection.sidebar = .alerts }
                    .keyboardShortcut("2")
                Button("Disk", systemImage: "internaldrive") { selection.sidebar = .disk }
                    .keyboardShortcut("3")
                Button("Hardware", systemImage: "cpu") { selection.sidebar = .hardware }
                    .keyboardShortcut("4")
                Button("Calendar", systemImage: "calendar") { selection.sidebar = .calendar }
                    .keyboardShortcut("5")
                Button("Energy", systemImage: "bolt") { selection.sidebar = .energy }
                    .keyboardShortcut("6")
                Divider()
                // The Disk screen's two panes, checked while one shows (S11).
                ForEach([(DiskPane.activity, "Disk Activity", "chart.xyaxis.line"), (.space, "Disk Space", "chart.pie")], id: \.0) { pane, title, symbol in
                    Toggle(title, systemImage: symbol, isOn: Binding(get: { selection.sidebar == .disk && selection.diskPane == pane },
                                                                     set: { _ in selection.sidebar = .disk; selection.diskPane = pane }))
                }
                Divider()
            }
                .labelStyle(.titleAndIcon)
        }
        CommandGroup(after: .sidebar) {
            Group {
                Button(selection.inspectorShown ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing") {
                    selection.inspectorShown.toggle()
                }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                // Options are checkmark toggles, as in More (S13); the inspector is a pane, so its title flips as Sidebar's does.
                Toggle("Show Chart", systemImage: "chart.xyaxis.line", isOn: Bindable(selection).showChart)
                    .disabled((selection.sidebar ?? .apps) != .apps)
                Toggle("Hide Quiet System Processes", systemImage: "eye.slash", isOn: Bindable(history).hideQuietSystem)
                    .disabled(selection.isSystem || selection.sidebar == .alerts)
                Toggle("Show Dismissed Alerts", systemImage: "eye", isOn: Bindable(alerts).showDismissed)
                    .disabled(selection.sidebar != .alerts)
                Button("Dismiss All Alerts", systemImage: "xmark.circle") { alerts.dismiss(alerts.undismissed(search: selection.search)) }
                    .disabled(selection.sidebar != .alerts || alerts.undismissed(search: selection.search).isEmpty)
                // Calendar: the double-click and Escape of the cells; Space: the folder above, as Escape; the charts: the zoom pill.
                Button("Zoom In", systemImage: "plus.magnifyingglass") {
                    if selection.sidebar == .calendar { calendar.selectedCell.map { calendar.zoomIn(at: $0.start) } } else { history.zoomIn() }
                }
                    .keyboardShortcut("]")
                    .disabled(selection.sidebar == .calendar ? calendar.selectedCell == nil || calendar.period.zoomedIn == nil
                              : !chartZoom || !history.canZoomIn)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                    if selection.showsSpace { diskMap.up() } else if selection.sidebar == .calendar { calendar.zoomOut() } else { history.zoomOut() }
                }
                    .keyboardShortcut("[")
                    .disabled(selection.showsSpace ? diskMap.focus.isEmpty
                              : selection.sidebar == .calendar ? calendar.period.zoomedOut == nil : !chartZoom || history.widerRange == nil)
                Divider()
                Button("Refresh", systemImage: "arrow.clockwise") { selection.refreshes += 1 }
                    .keyboardShortcut("r")
                    .disabled(!selection.isSystem || selection.sidebar == .energy || selection.showsSpace && diskMap.target == nil)
            }
                .labelStyle(.titleAndIcon)
        }
    }
}

/// File > New Group… in place of New Window: the app has one window.
struct GroupCommands: Commands {
    let selection: Selection
    let groups: GroupsModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("New App Group…", systemImage: "plus") { selection.editingGroup = .new }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    // While the sheet is open a new group would replace it and lose the draft.
                    .disabled(groups.loadError != nil || selection.editingGroup != nil)
            }
                .labelStyle(.titleAndIcon)
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
            Group {
                // One Live item: like the Live button, it starts Live and pauses back to the range before it.
                Button(history.range == .live ? "Pause Live Data" : "Start Live Data", systemImage: history.range == .live ? "pause" : "play") { history.toggleLive() }
                    .keyboardShortcut("l")
                    .disabled(noRange)
                Divider()
                ForEach(Array(HistoryRange.allCases.filter { $0 != .live }.enumerated()), id: \.offset) { i, range in
                    Toggle(range.label, isOn: Binding(get: { history.custom == nil && history.range == range }, set: { _ in history.range = range }))
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
                }
                .disabled(noRange)
                Divider()
                Button("Custom Range…", systemImage: "calendar") { selection.rangeShown = true }
                    .disabled(noRange)
            }
                .labelStyle(.titleAndIcon)
        }
        CommandMenu("Metric") {
            Group {
                ForEach(Array(history.metrics.enumerated()), id: \.offset) { i, metric in
                    Toggle(metric.label, isOn: Binding(get: { history.metric == metric }, set: { _ in history.metric = metric }))
                        // Digits 1 to 9 only: a 10th metric has no shortcut.
                        .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .control]) : nil)
                }
                .disabled(selection.isSystem && selection.sidebar != .calendar || selection.sidebar == .alerts)
            }
                .labelStyle(.titleAndIcon)
        }
    }
}

/// Acts on the selected app and the inspector's selected process; Quit goes through the same confirmation.
struct ProcessCommands: Commands {
    let selection: Selection

    var body: some Commands {
        CommandMenu("Process") {
            Group {
                Button(selection.app.map(selection.isPinned) == true ? "Unpin App from Sidebar" : "Pin App to Sidebar",
                       systemImage: selection.app.map(selection.isPinned) == true ? "pin.slash" : "pin") {
                    selection.app.map(selection.togglePin)
                }
                // The same shortcut as the File > Add to Sidebar action.
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled(selection.app == nil)
                Divider()
                Button("Quit Process…", systemImage: "xmark.circle") { request(SIGTERM) }
                    .keyboardShortcut("q", modifiers: [.command, .option])
                    .disabled(selection.signallable == nil)
                Button("Force Quit Process…", systemImage: "xmark.octagon") { request(SIGKILL) }
                    .disabled(selection.signallable == nil)
            }
                .labelStyle(.titleAndIcon)
        }
    }

    private func request(_ signal: Int32) {
        selection.signalRequest = selection.signallable.map { SignalRequest(process: $0, signal: signal) }
    }
}
