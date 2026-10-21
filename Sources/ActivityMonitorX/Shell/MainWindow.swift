import AMXCore
import AppKit
import SwiftUI

struct MainWindow: View {
    // SwiftUIMacros plugin is absent with Command Line Tools only, so @State is written out by hand.
    private let _selection = State<SidebarItem?>(initialValue: .timeline)
    private var selection: SidebarItem? { _selection.wrappedValue }
    private let _columns = State(initialValue: NavigationSplitViewVisibility.automatic)
    /// The group waiting for the Delete confirmation.
    private let _deleting = State<ProcessGroup?>(initialValue: nil)
    private let _deleteError = State<String?>(initialValue: nil)
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var appSelection
    @Environment(GroupsModel.self) private var groups

    var body: some View {
        NavigationSplitView(columnVisibility: _columns.projectedValue) {
            List(selection: _selection.projectedValue)  {
                Section("Monitor") {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                        .tag(SidebarItem.timeline)
                    Label("Apps", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.apps)
                }
                if let error = groups.loadError {
                    Section("Groups") {
                        Label("Groups unavailable", systemImage: "exclamationmark.triangle")
                            .help(error)
                    }
                } else {
                    Section {
                        ForEach(groups.groups) { group in
                            Label {
                                Text(group.name)
                            } icon: {
                                Image(systemName: group.symbol).foregroundStyle(group.color.color)
                            }
                            .badge(groups.scores[group.id].map { Text(Metric.score.format($0)) })
                            .tag(SidebarItem.group(group.id))
                            .contextMenu {
                                Button("Edit Group…") { appSelection.editingGroup = group }
                                Button("Delete Group…") { _deleting.wrappedValue = group }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Groups")
                            Spacer()
                            Button { appSelection.editingGroup = .new } label: { Label("New Group", systemImage: "plus").labelStyle(.iconOnly) }
                                .buttonStyle(.borderless)
                                .help("New Group")
                        }
                    }
                }
                if !appSelection.pinned.isEmpty {
                    Section("Pinned Apps") {
                        ForEach(appSelection.pinned.filter { appSelection.search.isEmpty || AppSearch.matches($0, appSelection.search) },
                                id: \.key) { app in
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
                case .group(let id): TimelineView(focus: nil, group: groups.groups.first { $0.id == id })
                }
            }
            // A new id drops toolbar layouts saved before Metric moved to the centre.
            .toolbar(id: "window") { MainToolbar(history: history, selection: appSelection) }
            .frame(minHeight: 480)
            // With the inspector open the window minimum is sidebar + this + twice the inspector's ideal width
            // (measured): 180 + 560 + 2 × 280 = 1300 pt, which leaves the detail the 840 pt its toolbar needs.
            .navigationSplitViewColumnWidth(min: 560, ideal: 980)
        }
        // At the top of the sidebar: the field takes no toolbar width, so Metric and Range never
        // go into » while searching. Find shows a hidden sidebar first, through the View menu's own action: setting
        // `columnVisibility` instead widens the window by the sidebar (measured).
        .searchable(text: Bindable(appSelection).query, isPresented: Bindable(appSelection).searchPresented, placement: .sidebar,
                    prompt: "App, process or PID")
        .onChange(of: appSelection.searchPresented) { _, shown in
            if shown, _columns.wrappedValue == .detailOnly {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
        }
        // The toolbar fits without » from a 1000 pt window (measured), with the sidebar shown or hidden. Applied here,
        // before the inspector, this minimum does not hold the inspector's width as well.
        .frame(minWidth: 1020)
        .inspector(isPresented: Bindable(appSelection).inspectorShown) {
            InspectorView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
        .focusedSceneValue(\.sidebarSelection, _selection.projectedValue)
        .modifier(SignalConfirmation())
        .sheet(item: Bindable(appSelection).editingGroup) { GroupEditor(group: $0) }
        .confirmationDialog("Delete “\(_deleting.wrappedValue?.name ?? "")”?",
                            isPresented: Binding(get: { _deleting.wrappedValue != nil }, set: { if !$0 { _deleting.wrappedValue = nil } }),
                            presenting: _deleting.wrappedValue) { group in
            Button("Delete", role: .destructive) {
                do { try groups.delete(group.id) } catch { _deleteError.wrappedValue = error.localizedDescription }
            }
        }
        .alert("Cannot Delete Group",
               isPresented: Binding(get: { _deleteError.wrappedValue != nil }, set: { if !$0 { _deleteError.wrappedValue = nil } }),
               presenting: _deleteError.wrappedValue) { _ in } message: { Text($0) }
        .onChange(of: selection) { _, item in
            appSelection.sidebar = item ?? .timeline
            if case .pinned(let app) = item { appSelection.app = app }
            scope(item)
        }
        .onChange(of: groups.groups) {
            guard case .group(let id) = selection else { return }
            if let group = groups.groups.first(where: { $0.id == id }) {
                history.show(group, metric: history.metric)
            } else {
                _selection.wrappedValue = .timeline
            }
        }
        .onChange(of: history.liveSettings) { live.settingsChanged() }
        .onChange(of: appSelection.pinned) {
            if case .pinned(let app) = selection, !appSelection.isPinned(app) { _selection.wrappedValue = .timeline }
        }
    }

    /// A group is shown by its Score; the Timeline never shows Score, so leaving a group resets it to CPU.
    private func scope(_ item: SidebarItem?) {
        if case .group(let id) = item, let group = groups.groups.first(where: { $0.id == id }) {
            history.show(group, metric: .score)
        } else {
            history.show(nil, metric: history.metric == .score ? .cpu : history.metric)
        }
    }
}
