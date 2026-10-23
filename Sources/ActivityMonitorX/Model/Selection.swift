import AMXCore
import Foundation
import Observation

/// The Disk screen's pills: Activity (rates, disks, volumes) or Space (the disk map).
enum DiskPane: String { case activity, space }

@Observable @MainActor
final class Selection {
    private static let pinnedKey = "pinnedApps", showChartKey = "showChart"

    /// The sidebar List's selection; Alerts and notifications navigate through it.
    var sidebar: SidebarItem? = .apps
    var app: AppKey? { didSet { if app != oldValue { process = nil } } }
    /// The inspector's selected process of `app`.
    var process: ProcessRank?
    /// A Quit / Force Quit waiting for confirmation.
    var signalRequest: SignalRequest?
    /// The group open in the editor sheet; a new one is not in `GroupsModel.groups` yet.
    var editingGroup: ProcessGroup?
    var inspectorShown = false
    /// The Custom Range popover: the range bar's Custom… button and Range > Custom Range open it.
    var rangeShown = false
    /// View > Refresh (⌘R) on a System screen: the shown screen re-reads what it otherwise reads once.
    var refreshes = 0
    var isSystem: Bool { sidebar?.isSystem == true }
    /// Opens or fronts the main window; set by views that have `openWindow`, for notification clicks.
    var openMain: (() -> Void)?
    /// The toolbar search text as typed; each screen filters what it lists (`SidebarItem.searchPrompt`). On app screens it
    /// also filters Pinned Apps and dims the chart's other apps.
    var query = ""
    /// Edit > Find sets it to focus the search field.
    var searchPresented = false
    /// `query` without the spaces around it, for `AppSearch`.
    var search: String { query.trimmingCharacters(in: .whitespaces) }
    var pinned: [AppKey] = UserDefaults.standard.data(forKey: Selection.pinnedKey)
        .flatMap { try? JSONDecoder().decode([AppKey].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(pinned), forKey: Self.pinnedKey) }
    }

    /// The selected process if it can be signalled: never pid ≤ 1, an exited pid has nothing to quit, and amxd refuses
    /// another user's process (D15), which `kill(pid, 0)` reports as EPERM. amxd still checks the start time.
    var signallable: ProcessRank? {
        process.flatMap { !$0.exited && $0.pid > 1 && kill($0.pid, 0) == 0 ? $0 : nil }
    }

    /// The Quit request: the selected process if it can be signalled, else, with no process selected, the app's running
    /// copies; nil when there is nothing to quit.
    func quitRequest(of app: AppKey) -> SignalRequest? {
        if let process = signallable { return SignalRequest(process: process, signal: SIGTERM) }
        guard process == nil, case let apps = InspectorView.running(app), !apps.isEmpty else { return nil }
        return SignalRequest(app: app.name, running: apps, signal: SIGTERM)
    }

    /// Opens Apps on an alert: the smallest range that holds its spell, the span around it on the chart, its app selected
    /// and not hidden by a search; a per-app or memory rule shows its metric.
    func reveal(_ event: EventMark, history: HistoryModel, rules: AlertRules) {
        let focus = EventFocus.window(for: event.ts, lookback: rules.lookback(rule: event.rule ?? ""), now: Date().timeIntervalSince1970)
        switch event.rule {
        case RuleName.memoryGrowth, RuleName.memoryJump: history.metric = .memory
        case RuleName.sustainedCPU, RuleName.systemCPU: history.metric = .cpu
        case RuleName.diskWrites: history.metric = .disk
        case RuleName.network: history.metric = .network
        case RuleName.energy: history.metric = .energy
        case RuleName.gpu: history.metric = .gpu
        default: break
        }
        app = event.app
        open(focus, history: history)
    }

    /// Opens Apps on a Calendar cell's time: the smallest range that holds it, the span on the chart.
    func reveal(from start: Double, to end: Double, history: HistoryModel) {
        open(EventFocus.window(from: start, to: end, now: Date().timeIntervalSince1970), history: history)
    }

    private func open(_ focus: (range: HistoryRange, span: ClosedRange<Double>?), history: HistoryModel) {
        // A range ends now (focus is relative to now) and clears a custom window and the span.
        history.range = focus.range
        history.span = focus.span
        query = ""
        showChart = true
        sidebar = .apps
    }

    /// Apps shows the chart above its table; off, the table fills the screen. Pinned apps and groups always show it.
    var showChart = UserDefaults.standard.object(forKey: Selection.showChartKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showChart, forKey: Self.showChartKey) }
    }

    /// Disk's pill, remembered. Before Space, Disk Map was a screen of its own: a start screen stored as it opens Space.
    var diskPane = DiskPane(rawValue: UserDefaults.standard.string(forKey: Selection.diskPaneKey) ?? "")
        ?? (Preferences.storedDiskMap ? .space : .activity) {
        didSet {
            UserDefaults.standard.set(diskPane.rawValue, forKey: Self.diskPaneKey)
            // The search finds volumes and disks on Activity, files on Space.
            if diskPane != oldValue { query = "" }
        }
    }
    private static let diskPaneKey = "diskPane"
    var showsSpace: Bool { sidebar == .disk && diskPane == .space }
    /// The screens that have the range bar and Live: Apps, pinned apps, groups and Disk's activity.
    var hasRange: Bool {
        switch sidebar ?? .apps {
        case .apps, .pinned, .group: true
        case .disk: !showsSpace
        default: false
        }
    }
    /// What the toolbar search finds on the shown screen.
    var searchPrompt: String { showsSpace ? "File or folder" : (sidebar ?? .apps).searchPrompt }

    func isPinned(_ app: AppKey) -> Bool { pinned.contains { $0.key == app.key } }

    func togglePin(_ app: AppKey) {
        if isPinned(app) { pinned.removeAll { $0.key == app.key } } else { pinned.append(app) }
    }
}
