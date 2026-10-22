import AMXCore
import AppKit
import SwiftUI

struct MainWindow: View {
    // SwiftUIMacros plugin is absent with Command Line Tools only, so @State is written out by hand.
    private let _columns = State(initialValue: NavigationSplitViewVisibility.automatic)
    /// The group waiting for the Delete confirmation.
    private let _deleting = State<ProcessGroup?>(initialValue: nil)
    private let _deleteError = State<String?>(initialValue: nil)
    /// Whether the inspector was open before a System screen closed it.
    private let _inspectorBeforeSystem = State(initialValue: false)
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var appSelection
    @Environment(GroupsModel.self) private var groups
    @Environment(AlertsModel.self) private var alerts
    @Environment(DiskMapModel.self) private var diskMap
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: _columns.projectedValue) {
            List(selection: Bindable(appSelection).sidebar) {
                Section("Monitor") {
                    Label("Timeline", systemImage: "chart.xyaxis.line")
                        .tag(SidebarItem.timeline)
                    Label("Apps", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.apps)
                    Label("Alerts", systemImage: "exclamationmark.triangle")
                        .badge(alerts.unread)
                        .tag(SidebarItem.alerts)
                }
                Section("System") {
                    Label("Disk", systemImage: "internaldrive")
                        .tag(SidebarItem.disk)
                    Label("Disk Map", systemImage: "square.grid.3x3.square")
                        .tag(SidebarItem.diskMap)
                    Label("Hardware", systemImage: "cpu")
                        .tag(SidebarItem.hardware)
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
                switch appSelection.sidebar ?? .timeline {
                case .timeline: TimelineView(focus: nil)
                case .apps: AppsView()
                case .alerts: AlertsView()
                case .pinned(let app): TimelineView(focus: app)
                case .group(let id): TimelineView(focus: nil, group: groups.groups.first { $0.id == id })
                case .disk: DiskView()
                case .diskMap: DiskMapView()
                case .hardware: HardwareView()
                }
            }
            // A new id drops toolbar layouts saved before Metric moved to the centre.
            .toolbar(id: "window") { MainToolbar(history: history, selection: appSelection, diskMap: diskMap) }
            .frame(minHeight: 480)
            // With the inspector open the window minimum is sidebar + this + twice the inspector's ideal width
            // (measured): 180 + 620 + 2 × 280 = 1360 pt, the width at which the toolbar fits with the inspector,
            // so a manual resize cannot push items into ».
            .navigationSplitViewColumnWidth(min: 620, ideal: 980)
        }
        // At the top of the sidebar: the field takes no toolbar width, so Metric and Range never
        // go into » while searching. Find shows a hidden sidebar first, through the View menu's own action: setting
        // `columnVisibility` instead widens the window by the sidebar (measured).
        .searchable(text: Bindable(appSelection).query, isPresented: Bindable(appSelection).searchPresented, placement: .sidebar,
                    prompt: "App, process or PID")
        // The inspector never shows an app the search hides from the tables; a pinned Timeline keeps its own app.
        .onChange(of: appSelection.search) { _, query in
            if case .pinned = appSelection.sidebar { return }
            guard let app = appSelection.app, !query.isEmpty else { return }
            let rank = history.range == .live ? live.rank(of: app) : history.rank(of: app)
            if AppSearch.filter(rank.map { [$0] } ?? [], query: query).isEmpty { appSelection.app = nil }
        }
        .onChange(of: appSelection.searchPresented) { _, shown in
            if shown, _columns.wrappedValue == .detailOnly {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
        }
        // The toolbar fits without » from a 1000 pt window (measured), with the sidebar shown or hidden; a group's 7th
        // segment (Score) from 1050 pt. Applied here, before the inspector, this minimum does not hold the inspector's
        // width as well, so a group with the inspector open asks for WindowFit's 1400 pt here.
        .frame(minWidth: history.scope == nil ? 1020 : appSelection.inspectorShown ? 1400 : 1060)
        .inspector(isPresented: Bindable(appSelection).inspectorShown) {
            InspectorView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
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
        .onChange(of: appSelection.sidebar) { old, item in
            if case .pinned(let app) = item { appSelection.app = app }
            scope(item)
            keepInspector(leaving: old)
        }
        .onChange(of: groups.groups) {
            guard case .group(let id) = appSelection.sidebar else { return }
            if let group = groups.groups.first(where: { $0.id == id }) {
                history.show(group, metric: history.metric)
            } else {
                appSelection.sidebar = .timeline
            }
        }
        .onChange(of: history.liveSettings) { live.settingsChanged() }
        .onChange(of: appSelection.pinned) {
            if case .pinned(let app) = appSelection.sidebar, !appSelection.isPinned(app) { appSelection.sidebar = .timeline }
        }
        // Activate after openWindow, or the window can open behind other apps (Task 0 probe 2). The menu bar label sets
        // the same closure, but it does not exist while the item is hidden in Settings.
        .onAppear { appSelection.openMain = { [openWindow] in openWindow(id: "main"); NSApp.activate() } }
    }

    /// System screens have no inspector: it closes on entering one and comes back as it was on leaving.
    private func keepInspector(leaving old: SidebarItem?) {
        switch (old?.isSystem == true, appSelection.isSystem) {
        case (false, true):
            _inspectorBeforeSystem.wrappedValue = appSelection.inspectorShown
            appSelection.inspectorShown = false
        case (true, false) where _inspectorBeforeSystem.wrappedValue && !appSelection.inspectorShown:
            WindowFit.toggleInspector(appSelection, score: history.scope != nil)
        default: break
        }
    }

    /// A group is shown by its Score; the Timeline never shows Score, so leaving a group resets it to CPU.
    private func scope(_ item: SidebarItem?) {
        if case .group(let id) = item, let group = groups.groups.first(where: { $0.id == id }) {
            history.show(group, metric: .score)
            WindowFit.fitScore(inspector: appSelection.inspectorShown)
        } else {
            history.show(nil, metric: history.metric == .score ? .cpu : history.metric)
        }
    }
}
