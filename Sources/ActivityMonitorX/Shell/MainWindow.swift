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
    /// The detail area's width, for the toolbar: items cannot read the room they have. The inspector pane lives inside
    /// the detail area, so it does not change the room the toolbar has.
    private let _width = State(initialValue: CGFloat(1000))
    /// The inspector pane's width, remembered; `InspectorPane` keeps it between 240 and 400 pt.
    @AppStorage("inspectorWidth") private var inspectorWidth = 280.0

    /// Metric falls back to a menu where its segments no longer fit. Measured with the segments forced on, in a 1020 pt window
    /// (the least it opens at): with the sidebar shown everything fits from 756 pt of detail and Range, Hide Quiet and Inspector
    /// go into » at 752, with or without the Score segment; a hidden sidebar leaves 1020 pt or more, which fits.
    private var compactToolbar: Bool { _width.wrappedValue < 760 }

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
                if let error = groups.loadError {
                    Section("Groups") {
                        Label("Groups unavailable", systemImage: "exclamationmark.triangle")
                            .help(error)
                    }
                } else {
                    Section {
                        if groups.groups.isEmpty {
                            Button("Add a Group…") { appSelection.editingGroup = .new }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
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
                                .padding(.trailing, 6)
                        }
                    }
                }
                Section("System") {
                    Label("Disk", systemImage: "internaldrive")
                        .tag(SidebarItem.disk)
                    Label("Disk Map", systemImage: "square.grid.3x3.square")
                        .tag(SidebarItem.diskMap)
                    Label("Hardware", systemImage: "cpu")
                        .tag(SidebarItem.hardware)
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
            // At the top of the sidebar: the field takes no toolbar width, so Metric and Range never
            // go into » while searching. Find shows a hidden sidebar first, through the View menu's own action: setting
            // `columnVisibility` instead widens the window by the sidebar (measured).
            .modifier(SidebarSearch(selection: appSelection))
        } detail: {
            GeometryReader { proxy in
                InspectorPane(shown: appSelection.inspectorShown, width: $inspectorWidth, available: proxy.size.width) {
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
                .onChange(of: proxy.size.width, initial: true) { _, width in _width.wrappedValue = width }
            }
            // A new id drops toolbar layouts saved before Metric moved to the centre.
            .toolbar(id: "window") { MainToolbar(history: history, selection: appSelection, diskMap: diskMap, compact: compactToolbar) }
            .frame(minHeight: 480)
            .navigationSplitViewColumnWidth(min: 620, ideal: 980)
        }
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
            if appSelection.isSystem { appSelection.query = "" }
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
            appSelection.inspectorShown = true
        default: break
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

/// The sidebar search field, on process screens only: System screens show no app data to search.
private struct SidebarSearch: ViewModifier {
    let selection: Selection

    func body(content: Content) -> some View {
        if selection.isSystem {
            content
        } else {
            content.searchable(text: Bindable(selection).query, isPresented: Bindable(selection).searchPresented, placement: .sidebar,
                               prompt: "App, process or PID")
        }
    }
}

/// The least width the content keeps beside the inspector pane.
private let contentMin = 380.0

/// The content with the inspector as a trailing pane inside it: opening it shrinks the content, never the window.
/// A divider drags its width (240 to 400 pt, remembered); the content keeps `contentMin` (380 pt) beside it.
private struct InspectorPane<Content: View>: View {
    let shown: Bool
    @Binding var width: Double
    let available: CGFloat
    @ViewBuilder let content: Content
    private let _dragStart = State<Double?>(initialValue: nil)

    private var maxWidth: Double { max(200, min(400, Double(available) - contentMin - 1)) }
    /// 240 to 400 pt, less where the window leaves the content under `contentMin`; the stored width stays inside this too.
    private func clamp(_ value: Double) -> Double { min(max(value, min(240, maxWidth)), maxWidth) }
    private var paneWidth: Double { clamp(width) }

    var body: some View {
        HStack(spacing: 0) {
            content.frame(minWidth: contentMin, maxWidth: .infinity)
            if shown {
                Divider()
                    .overlay {
                        Color.clear.frame(width: 8).contentShape(Rectangle())
                            .pointerStyle(.columnResize)
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { drag in
                                    let start = _dragStart.wrappedValue ?? paneWidth
                                    _dragStart.wrappedValue = start
                                    width = clamp(start - drag.translation.width)
                                }
                                .onEnded { _ in _dragStart.wrappedValue = nil })
                            .accessibilityElement()
                            .accessibilityLabel("Inspector width")
                            .accessibilityValue("\(Int(paneWidth)) points")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: width = clamp(paneWidth + 20)
                                case .decrement: width = clamp(paneWidth - 20)
                                @unknown default: break
                                }
                            }
                    }
                InspectorView()
                    .frame(width: paneWidth)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector")
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: shown)
    }
}
