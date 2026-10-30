import AMXCore
import AppKit
import SwiftUI

struct MainWindow: View {
    // SwiftUIMacros plugin is absent with Command Line Tools only, so @State is written out by hand.
    private let _columns = State(initialValue: NavigationSplitViewVisibility.automatic)
    /// The group waiting for the Delete confirmation.
    private let _deleting = State<ProcessGroup?>(initialValue: nil)
    private let _deleteError = State<String?>(initialValue: nil)
    /// The pinned app whose Alert Rules sheet is open.
    private let _rulesApp = State<AppKey?>(initialValue: nil)
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var appSelection
    @Environment(GroupsModel.self) private var groups
    @Environment(AlertsModel.self) private var alerts
    @Environment(DiskMapModel.self) private var diskMap
    @Environment(Preferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    /// Whether the detail area is too narrow for the Metric segments: toolbar items cannot read the room they have, so
    /// `ToolbarFit` compares the detail width with the measured widths of the toolbar's parts. Only a crossing changes it,
    /// so a live resize does not rebuild the window at each point. The inspector pane lives inside the detail area, so it
    /// does not change the room the toolbar has.
    private let _compact = State(initialValue: false)
    private let _fit = State(initialValue: ToolbarFit())
    /// Whether the detail area is too narrow for the title pill's text: the pill shows its icon only.
    private let _narrow = State(initialValue: false)
    /// The inspector pane's width, remembered; `InspectorPane` keeps it between 240 and 400 pt.
    @AppStorage("inspectorWidth") private var inspectorWidth = 280.0

    private static let narrowBelow: CGFloat = 700

    @AppStorage("sidebarGroupsExpanded") private var groupsExpanded = true
    @AppStorage("sidebarPinnedExpanded") private var pinnedExpanded = true

    private static let monitorKey = "sidebarOrderMonitor"
    private static let systemKey = "sidebarOrderSystem"
    private static let monitorDefaults = ["apps", "calendar", "alerts"]
    private static let systemDefaults = ["disk", "hardware", "energy"]
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
        case "energy": Label("Energy", systemImage: "bolt").tag(SidebarItem.energy)
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
                            .help(group.name)
                            .badge(groups.scores[group.id].map { Text(Metric.score.format($0)) })
                            .tag(SidebarItem.group(group.id))
                            .contextMenu {
                                Group {
                                    Button("Edit Group…", systemImage: "pencil") { appSelection.editingGroup = group }
                                        .help("Edit the name, colour and rules of \(group.name)")
                                    Button("Delete Group…", systemImage: "trash") { _deleting.wrappedValue = group }
                                        .help("Delete the group \(group.name), after you confirm")
                                }
                                    .labelStyle(.titleAndIcon)
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
                        ForEach(appSelection.pinned.filter {
                            appSelection.search.isEmpty || appSelection.sidebar?.searchesApps == false || AppSearch.matches($0, appSelection.search)
                        },
                                id: \.key) { app in
                            PinnedRow(app: app, history: history, selection: appSelection, rulesApp: _rulesApp.projectedValue)
                                .tag(SidebarItem.pinned(app))
                        }
                    }
                }
            }
            // Pin and Unpin: the row fades in or out.
            .animation(Motion.fade(), value: appSelection.pinned.map(\.key))
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                Button { appSelection.editingGroup = .new } label: { Label("Add Group", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .help("Add a group of apps to the sidebar")
                    .disabled(groups.loadError != nil || appSelection.editingGroup != nil)
                    .padding(.horizontal, Layout.padding)
                    .padding(.vertical, Layout.inset)
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
                    case .hardware: HardwareView()
                    case .energy: EnergyView()
                    }
                }
                .environment(\.narrowDetail, _narrow.wrappedValue)
                .environment(_fit.wrappedValue)
                .onChange(of: proxy.size.width < Self.narrowBelow, initial: true) { _, narrow in _narrow.wrappedValue = narrow }
                .onChange(of: _fit.wrappedValue.compact(width: proxy.size.width, searching: appSelection.searchPresented || !appSelection.query.isEmpty,
                                                        was: _compact.wrappedValue), initial: true) { _, compact in
                    // Next turn: the flip removes the segments, which the toolbar may be laying out right now.
                    Task { @MainActor in _compact.wrappedValue = compact }
                }
            }
            // No toolbar background: the content runs under the toolbar row with the scroll edge effect, and the items
            // float as glass capsules. Each screen's title pill (`screenTitle`) replaces the system title.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            // A new id drops toolbar layouts saved before the system toggle went and the Sidebar button came.
            .toolbar(id: "window3") { MainToolbar(history: history, selection: appSelection, diskMap: diskMap, compact: _compact.wrappedValue, fit: _fit.wrappedValue) }
            .background { ToolbarSearch(selection: appSelection) }
            // The segments laid out off screen, for their ideal width: the pop-up shows instead of them while the room is short.
            .background {
                MetricPicker(history: history).pickerStyle(.segmented).fixedSize().opacity(0).allowsHitTesting(false).disabled(true).accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _fit.wrappedValue.ideal = $0 }
                    .onChange(of: history.metrics.count, initial: true) { _, count in _fit.wrappedValue.count = count }
            }
            .frame(minHeight: 480)
            .navigationSplitViewColumnWidth(min: 620, ideal: 980)
        }
        // The inspector never shows an app the search hides from the tables; a pinned app's screen keeps its app.
        .onChange(of: appSelection.search) { _, query in
            if case .pinned = appSelection.sidebar { return }
            guard appSelection.sidebar?.searchesApps != false, let app = appSelection.app, !query.isEmpty else { return }
            let rank = history.range == .live ? live.rank(of: app) : history.rank(of: app)
            if AppSearch.filter(rank.map { [$0] } ?? [], query: query).isEmpty { appSelection.app = nil }
        }
        .modifier(SignalConfirmation())
        .sheet(item: Bindable(appSelection).editingGroup) { GroupEditor(group: $0) }
        .sheet(isPresented: Binding(get: { _rulesApp.wrappedValue != nil }, set: { if !$0 { _rulesApp.wrappedValue = nil } })) {
            if let app = _rulesApp.wrappedValue { AppRulesSheet(app: app) }
        }
        .confirmationDialog("Delete “\(_deleting.wrappedValue?.name ?? "")”?",
                            isPresented: Binding(get: { _deleting.wrappedValue != nil }, set: { if !$0 { _deleting.wrappedValue = nil } }),
                            presenting: _deleting.wrappedValue) { group in
            Button("Delete Group", role: .destructive) {
                do { try groups.delete(group.id) } catch { _deleteError.wrappedValue = error.localizedDescription }
            }
        }
        .alert("Cannot Delete Group",
               isPresented: Binding(get: { _deleteError.wrappedValue != nil }, set: { if !$0 { _deleteError.wrappedValue = nil } }),
               presenting: _deleteError.wrappedValue) { _ in } message: { Text($0) }
        // Hardware and Calendar read none of the loaded history: it does not reload under them, also at launch.
        .onChange(of: appSelection.sidebar, initial: true) { _, item in history.paused = item == .hardware || item == .calendar }
        .onChange(of: appSelection.sidebar) { old, item in
            if case .pinned(let app) = item { appSelection.app = app }
            scope(item)
            // Only the app charts draw the span, and Zoom In would use a span the screen does not show.
            if item == .disk || !appSelection.hasRange { history.span = nil }
            // One query for all screens: it stays between screens that search apps, and is cleared where it would name
            // another kind of item (a volume, a file, a hardware row).
            if old?.searchesApps != true || item?.searchesApps != true { appSelection.query = "" }
            if let item, let screen = StartScreen(item) { preferences.lastScreen = screen }
        }
        .onChange(of: history.range) { _, range in preferences.lastRange = StartRange(range) }
        // Live polls only in Live: Start Live starts the loop, so it polls at once.
        .task(id: history.range == .live) { await live.run() }
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

/// Search in the trailing toolbar on every screen, prompted with what the screen lists. The toolbar's magnifier until it
/// is clicked (or ⌘F); then the system field, until it is empty and loses focus (Escape, a click elsewhere, or the clear
/// button and then a click elsewhere). macOS has no `searchToolbarBehavior(.minimize)`. A background view hosts it, so
/// the swap never rebuilds the screen.
private struct ToolbarSearch: View {
    let selection: Selection
    private let _focused = FocusState<Bool>()

    var body: some View {
        if selection.searchPresented || !selection.query.isEmpty {
            Color.clear.searchable(text: Bindable(selection).query, isPresented: Bindable(selection).searchPresented,
                                   placement: .toolbar, prompt: selection.searchPrompt)
                .searchFocused(_focused.projectedValue)
                // A query keeps the field: it closes when the query is cleared later, outside the field.
                .onChange(of: _focused.wrappedValue) { _, focused in if !focused { selection.searchPresented = false } }
        } else {
            Color.clear
        }
    }
}

/// The inspector of the shown screen: each shows what its screen has selected, or a summary.
private struct ScreenInspector: View {
    @Environment(Selection.self) private var selection

    var body: some View {
        Group {
            switch selection.sidebar ?? .apps {
            case .calendar: CalendarInspector()
            case .disk where selection.diskPane == .space: DiskMapInspector()
            case .disk: DiskInspector()
            case .hardware: HardwareInspector()
            case .energy where selection.app == nil: EnergyInspector()
            default: InspectorView()
            }
        }
    }
}

/// The least width the content keeps beside the inspector pane.
private let contentMin = 380.0

/// The content with the inspector as a trailing floating panel inside it: opening it shrinks the content, never the window.
/// The 8 pt gap before the panel drags its width (240 to 400 pt, remembered); the content keeps `contentMin` (380 pt)
/// beside it. The panel starts 8 pt below the toolbar row: a full-height panel would put the window's trailing toolbar
/// items over it, because those items always end at the window edge.
private struct InspectorPane<Content: View>: View {
    let shown: Bool
    @Binding var width: Double
    let available: CGFloat
    @ViewBuilder let content: Content
    /// Read here, not per call, so the transition below follows a change of the setting at once.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let _dragStart = State<Double?>(initialValue: nil)

    private var maxWidth: Double { max(200, min(400, Double(available) - contentMin - 2 * Layout.inset)) }
    /// 240 to 400 pt, less where the window leaves the content under `contentMin`; the stored width stays inside this too.
    private func clamp(_ value: Double) -> Double { min(max(value, min(240, maxWidth)), maxWidth) }
    private var paneWidth: Double { clamp(width) }

    var body: some View {
        HStack(spacing: 0) {
            content.frame(minWidth: contentMin, maxWidth: .infinity)
            if shown {
                Color.clear.frame(width: Layout.inset).contentShape(Rectangle())
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
                ScreenInspector()
                    .frame(width: paneWidth)
                    .frame(maxHeight: .infinity)
                    // The grouped forms and lists hide their own opaque background, so the panel's glass shows behind
                    // their sections, as behind the empty states: one surface for every inspector.
                    .scrollContentBackground(.hidden)
                    // The panel starts below the toolbar row, so it needs no edge effect at its top.
                    .scrollEdgeEffectHidden(true, for: .top)
                    .floatingPanel()
                    .padding([.vertical, .trailing], Layout.inset)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector")
                    .transition(reduceMotion || !Motion.on ? .opacity : .move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.fade(0.25), value: shown)
    }
}
