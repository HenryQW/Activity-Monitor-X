import SwiftUI

@main
struct ActivityMonitorXApp: App {
    private let history: HistoryModel
    private let live: LiveModel
    private let selection = Selection()
    private let groups: GroupsModel

    init() {
        let history = HistoryModel()
        self.history = history
        live = LiveModel(history: history)
        groups = GroupsModel(history: history)
    }

    var body: some Scene {
        Window("Activity Monitor X", id: "main") {
            MainWindow()
                .environment(history)
                .environment(live)
                .environment(selection)
                .environment(groups)
                .task { await history.run() }
                .task { await groups.run() }
                .task { await live.run() }
        }
        .defaultSize(width: 1200, height: 760)
        .defaultLaunchBehavior(.presented)
        .commands {
            SidebarCommands()
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { selection.searchPresented = true }
                    .keyboardShortcut("f")
            }
            GroupCommands(selection: selection, groups: groups)
            GoCommands(selection: selection, history: history)
            DataCommands(history: history)
            ProcessCommands(selection: selection)
        }
    }
}
