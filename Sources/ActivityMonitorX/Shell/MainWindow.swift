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
    @Environment(Preferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    /// Whether the detail area is too narrow for the Metric segments: toolbar items cannot read the room they have. Only a
    /// crossing of the threshold changes it, so a live resize does not rebuild the window at each point. The inspector pane
    /// lives inside the detail area, so it does not change the room the toolbar has.
    private let _compact = State(initialValue: false)
    /// The inspector pane's width, remembered; `InspectorPane` keeps it between 240 and 400 pt.
    @AppStorage("inspectorWidth") private var inspectorWidth = 280.0

    /// Metric falls back to a menu where its segments no longer fit. Measured on Apps (the most items, with Show Chart) with the
    /// 180 pt sidebar shown and the Live toggle: everything fits from 900 pt of detail (window 860 to 1300 checked).
    private static let compactBelow: CGFloat = 900

    @AppStorage("sidebarGroupsExpanded") private var groupsExpanded = true
    @AppStorage("sidebarPinnedExpanded") private var pinnedExpanded = true

    private static let monitorKey = "sidebarOrderMonitor"
    private static let systemKey = "sidebarOrderSystem"
    private static let monitorDefaults = ["apps", "calendar", "alerts"]
    private static let systemDefaults = ["disk", "diskMap", "hardware", "energy"]
    /// The saved order of the Monitor and System items; a drag stays inside its section.
    private let _monitorOrder = State(initialValue: MainWindow.load(monitorKey, monitorDefaults))
    private let _systemOrder = State(initialValue: MainWindow.load(systemKey, systemDefaults))

    private static func load(_ key: String, _ defaults: [String]) -> [String] {
        SidebarOrder.merge(saved: UserDefaults.standard.stringArray(forKey: key) ?? [], defaults: defaults)
    }

    private func move(_ from: IndexSet, _ to: Int, of order: State<[String]>, key: String) {
        order.wrappedValue.move(fromOffsets: from, toOffset: to)
        UserDefaults.standard.set(order.wrappedValue, forKey: key)
    }

    @ViewBuilder private func row(_ id: String) -> some View {
        switch id {
        case "apps": Label("Apps", systemImage: "square.grid.2x2").tag(SidebarItem.apps)
        case "calendar": Label("Calendar", systemImage: "calendar").tag(SidebarItem.calendar)
        case "alerts": Label("Alerts", systemImage: "exclamationmark.triangle").badge(alerts.unread)
                .badgeProminence(alerts.hasUnreadCritical ? .increased : .standard).tag(SidebarItem.alerts)
        case "disk": Label("Disk", systemImage: "internaldrive").tag(SidebarItem.disk)
        case "diskMap": Label("Disk Map", systemImage: "square.grid.3x3.square").tag(SidebarItem.diskMap)
        case "energy": Label("Energy", systemImage: "bolt.fill").tag(SidebarItem.energy)
        default: Label("Hardware", systemImage: "cpu").tag(SidebarItem.hardware)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: _columns.projectedValue) {
            List(selection: Bindable(appSelection).sidebar) {
                Section("Monitor") {
                    ForEach(_monitorOrder.wrappedValue, id: \.self) { row($0) }
                        .onMove { move($0, $1, of: _monitorOrder, key: Self.monitorKey) }
                }
                if let error = groups.loadError {
                    Section("Groups") {
                        Label("Groups unavailable", systemImage: "exclamationmark.triangle")
                            .help(error)
                    }
                } else if !groups.groups.isEmpty {
                    // An empty Groups section is hidden: the Add Group footer creates the first group.
                    Section("Groups", isExpanded: $groupsExpanded) {
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
                    }
                }
                Section("System") {
                    ForEach(_systemOrder.wrappedValue, id: \.self) { row($0) }
                        .onMove { move($0, $1, of: _systemOrder, key: Self.systemKey) }
                }
                if !appSelection.pinned.isEmpty {
                    Section("Pinned Apps", isExpanded: $pinnedExpanded) {
                        ForEach(appSelection.pinned.filter { appSelection.search.isEmpty || AppSearch.matches($0, appSelection.search) },
                                id: \.key) { app in
                            Label(app.name, systemImage: "pin")
                                .help(app.key)
                                .tag(SidebarItem.pinned(app))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                Button { appSelection.editingGroup = .new } label: { Label("Add Group", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .help("Add a group of apps")
                    .disabled(groups.loadError != nil || appSelection.editingGroup != nil)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            .toolbar { SidebarButton(shown: _columns.wrappedValue != .detailOnly) }
            // The system toggle is removed: in a customizable toolbar it lands in » and costs two clicks. `SidebarButton`
            // replaces it. It is removed from the sidebar column, where the system adds it.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            GeometryReader { proxy in
                InspectorPane(shown: appSelection.inspectorShown, width: $inspectorWidth, available: proxy.size.width) {
                    switch appSelection.sidebar ?? .apps {
                    case .apps: TimelineView(focus: nil)
                    case .calendar: CalendarView()
                    case .alerts: AlertsView()
                    case .pinned(let app): TimelineView(focus: app)
                    case .group(let id): TimelineView(focus: nil, group: groups.groups.first { $0.id == id })
                    case .disk: DiskView()
                    case .diskMap: DiskMapView()
                    case .hardware: HardwareView()
                    case .energy: EnergyView()
                    }
                }
                .onChange(of: proxy.size.width < Self.compactBelow, initial: true) { _, compact in _compact.wrappedValue = compact }
            }
            // A new id drops toolbar layouts saved before the system toggle went and the Sidebar button came.
            // A solid toolbar: content and the inspector pane do not show through it, so it keeps one colour across the window.
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbar(id: "window3") { MainToolbar(history: history, selection: appSelection, diskMap: diskMap, compact: _compact.wrappedValue) }
            .background { ToolbarSearch(selection: appSelection) }
            .frame(minHeight: 480)
            .navigationSplitViewColumnWidth(min: 620, ideal: 980)
        }
        // The inspector never shows an app the search hides from the tables; a pinned app's screen keeps its app.
        .onChange(of: appSelection.search) { _, query in
            if case .pinned = appSelection.sidebar { return }
            guard let app = appSelection.app, !query.isEmpty else { return }
            let rank = history.range == .live ? live.rank(of: app) : history.rank(of: app)
            if AppSearch.filter(rank.map { [$0] } ?? [], query: query).isEmpty { appSelection.app = nil }
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
            if let item, let screen = StartScreen(item) { preferences.lastScreen = screen }
        }
        .onChange(of: history.range) { _, range in preferences.lastRange = StartRange(range) }
        .onChange(of: groups.groups) {
            guard case .group(let id) = appSelection.sidebar else { return }
            if let group = groups.groups.first(where: { $0.id == id }) {
                history.show(group, metric: history.metric)
            } else {
                appSelection.sidebar = .apps
            }
        }
        .onChange(of: history.liveSettings) { live.settingsChanged() }
        .onChange(of: appSelection.pinned) {
            if case .pinned(let app) = appSelection.sidebar, !appSelection.isPinned(app) { appSelection.sidebar = .apps }
        }
        // Activate after openWindow, or the window can open behind other apps (Task 0 probe 2). The menu bar label sets
        // the same closure, but it does not exist while the item is hidden in Settings.
        .onAppear {
            guard !preferences.startApplied else { return }
            preferences.startApplied = true
            appSelection.sidebar = preferences.startScreen
            history.range = preferences.startRange
        }
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

    /// A group is shown by its Score; Apps never shows Score, so leaving a group resets it to CPU.
    private func scope(_ item: SidebarItem?) {
        if case .group(let id) = item, let group = groups.groups.first(where: { $0.id == id }) {
            history.show(group, metric: .score)
        } else {
            history.show(nil, metric: history.metric == .score ? .cpu : history.metric)
        }
    }
}

/// One Sidebar button, at the leading edge right after the window buttons, shown or hidden. `.navigation` items are not
/// customizable, so they never go into ». It belongs to the sidebar column and stays in the toolbar while the sidebar is
/// hidden. Toggles through the responder chain, like the View menu's
/// command: setting `columnVisibility` instead widens the window by the sidebar (measured).
private struct SidebarButton: ToolbarContent {
    let shown: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(shown ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .labelStyle(.iconOnly)
            .help(shown ? "Hide the sidebar" : "Show the sidebar")
        }
    }
}

/// Search in the trailing toolbar, on process screens only: System screens show no app data to search. The toolbar's
/// magnifier until it is clicked (or ⌘F); then the system field, until it is cancelled while empty. macOS has no
/// `searchToolbarBehavior(.minimize)`. A background view hosts it, so the swap never rebuilds the screen.
private struct ToolbarSearch: View {
    let selection: Selection

    var body: some View {
        if selection.isSystem {
            Color.clear
        } else if selection.searchPresented || !selection.query.isEmpty {
            Color.clear.searchable(text: Bindable(selection).query, isPresented: Bindable(selection).searchPresented,
                                   placement: .toolbar, prompt: "App, process or PID")
        } else {
            Color.clear
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
                            .help("Drag to change the inspector width")
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
                    .background(.regularMaterial, ignoresSafeAreaEdges: [])
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector")
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: shown)
    }
}
