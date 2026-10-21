import AMXCore
import Foundation
import Observation

@Observable @MainActor
final class Selection {
    private static let pinnedKey = "pinnedApps"

    var sidebar: SidebarItem = .timeline
    var app: AppKey? { didSet { if app != oldValue { process = nil } } }
    /// The inspector's selected process of `app`.
    var process: ProcessRank?
    /// A Quit / Force Quit waiting for confirmation.
    var signalRequest: SignalRequest?
    var inspectorShown = false
    var pinned: [AppKey] = UserDefaults.standard.data(forKey: Selection.pinnedKey)
        .flatMap { try? JSONDecoder().decode([AppKey].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(pinned), forKey: Self.pinnedKey) }
    }

    /// The selected process if it can be signalled: never pid ≤ 1, and an exited pid has nothing to quit
    /// (EPERM means it exists under another user). amxd still checks the start time against pid reuse.
    var signallable: ProcessRank? {
        process.flatMap { !$0.exited && $0.pid > 1 && (kill($0.pid, 0) == 0 || errno == EPERM) ? $0 : nil }
    }

    func isPinned(_ app: AppKey) -> Bool { pinned.contains { $0.key == app.key } }

    func togglePin(_ app: AppKey) {
        if isPinned(app) { pinned.removeAll { $0.key == app.key } } else { pinned.append(app) }
    }
}
