import AMXCore
import Foundation
import Observation

@Observable @MainActor
final class Selection {
    private static let pinnedKey = "pinnedApps"

    /// The sidebar List's selection; Alerts and notifications navigate through it.
    var sidebar: SidebarItem? = .timeline
    var app: AppKey? { didSet { if app != oldValue { process = nil } } }
    /// The inspector's selected process of `app`.
    var process: ProcessRank?
    /// A Quit / Force Quit waiting for confirmation.
    var signalRequest: SignalRequest?
    /// The group open in the editor sheet; a new one is not in `GroupsModel.groups` yet.
    var editingGroup: ProcessGroup?
    var inspectorShown = false
    /// View > Refresh (⌘R) on a System screen: the shown screen re-reads what it otherwise reads once.
    var refreshes = 0
    var isSystem: Bool { sidebar?.isSystem == true }
    /// Opens or fronts the main window; set by views that have `openWindow`, for notification clicks.
    var openMain: (() -> Void)?
    /// Sidebar search text as typed; filters the tables and Pinned Apps and dims the chart's other apps.
    var query = ""
    /// Edit > Find sets it to focus the search field.
    var searchPresented = false
    /// `query` without the spaces around it, for `AppSearch`.
    var search: String { query.trimmingCharacters(in: .whitespaces) }

    /// While searching, the match count ahead of the range's own subtitle ("4 of 98 apps · Since 11:06 PM").
    func subtitle(_ range: String, shown: Int, of all: Int) -> String {
        search.isEmpty ? range : ["\(shown) of \(all) apps", range].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var pinned: [AppKey] = UserDefaults.standard.data(forKey: Selection.pinnedKey)
        .flatMap { try? JSONDecoder().decode([AppKey].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(pinned), forKey: Self.pinnedKey) }
    }

    /// The selected process if it can be signalled: never pid ≤ 1, an exited pid has nothing to quit, and amxd refuses
    /// another user's process (D15), which `kill(pid, 0)` reports as EPERM. amxd still checks the start time.
    var signallable: ProcessRank? {
        process.flatMap { !$0.exited && $0.pid > 1 && kill($0.pid, 0) == 0 ? $0 : nil }
    }

    /// Opens the Timeline on an alert: the smallest range that holds its spell, the span around it, its app selected
    /// and not hidden by a search; memory rules show Memory, the CPU rule CPU.
    func reveal(_ event: EventMark, history: HistoryModel, rules: AlertRules) {
        let focus = EventFocus.window(for: event.ts, lookback: rules.lookback(rule: event.rule ?? ""), now: Date().timeIntervalSince1970)
        if event.rule == RuleName.memoryGrowth || event.rule == RuleName.memoryJump { history.metric = .memory }
        if event.rule == RuleName.sustainedCPU { history.metric = .cpu }
        // The range first: a range change clears the span.
        history.range = focus.range
        history.span = focus.span
        query = ""
        app = event.app
        sidebar = .timeline
    }

    func isPinned(_ app: AppKey) -> Bool { pinned.contains { $0.key == app.key } }

    func togglePin(_ app: AppKey) {
        if isPinned(app) { pinned.removeAll { $0.key == app.key } } else { pinned.append(app) }
    }
}
