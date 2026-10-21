import SwiftUI

struct MainWindow: View {
    // SwiftUIMacros plugin is absent with Command Line Tools only, so @State is written out by hand.
    private let _selection = State<SidebarItem?>(initialValue: .timeline)
    private var selection: SidebarItem? { _selection.wrappedValue }
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var appSelection

    var body: some View {
        NavigationSplitView {
            List(selection: _selection.projectedValue)  {
                Section("Monitor") {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                        .tag(SidebarItem.timeline)
                    Label("Apps", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.apps)
                }
                if !appSelection.pinned.isEmpty {
                    Section("Pinned Apps") {
                        ForEach(appSelection.pinned, id: \.key) { app in
                            Label(app.name, systemImage: "pin")
                                .help(app.key)
                                .tag(SidebarItem.pinned(app))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            Group {
                switch selection ?? .timeline {
                case .timeline: TimelineView(focus: nil)
                case .apps: AppsView()
                case .pinned(let app): TimelineView(focus: app)
                }
            }
            .toolbar(id: "main") { MainToolbar(history: history, selection: appSelection) }
        }
        .inspector(isPresented: Bindable(appSelection).inspectorShown) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 340)
        }
        .focusedSceneValue(\.sidebarSelection, _selection.projectedValue)
        .modifier(SignalConfirmation())
        .onChange(of: selection) { _, item in
            appSelection.sidebar = item ?? .timeline
            if case .pinned(let app) = item { appSelection.app = app }
        }
        .onChange(of: history.metric) { live.settingsChanged() }
        .onChange(of: history.hideQuietSystem) { live.settingsChanged() }
        .onChange(of: appSelection.pinned) {
            if case .pinned(let app) = selection, !appSelection.isPinned(app) { _selection.wrappedValue = .timeline }
        }
    }
}
