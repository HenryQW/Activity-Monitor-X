import AMXCore
import Foundation
import Observation
import os

/// Alert rows for the Alerts screen, its unread badge and notifications. Runs for the app's whole life, also with the
/// window closed (M4-D8): one indexed query by row id every 15 s.
@Observable @MainActor
final class AlertsModel {
    private static let readKey = "alertsReadThrough"
    private static let notifiedKey = "alertsNotifiedThrough"
    private static let dismissedKey = "alertsDismissed"
    nonisolated private static let limit = 500
    private static let log = Logger(subsystem: AMX.bundleID, category: "alerts")

    /// Newest first, at most `limit`.
    private(set) var alerts: [EventMark] = []
    /// Rows up to this id are read (M4-D9).
    private(set) var readThrough = UserDefaults.standard.object(forKey: AlertsModel.readKey) as? Int64 ?? 0 {
        didSet { UserDefaults.standard.set(readThrough, forKey: Self.readKey) }
    }
    /// Dismissed alerts are hidden unless `showDismissed`; the app keeps them, the daemon stays the only database writer (D33).
    private(set) var dismissed = DismissedSet(ids: (UserDefaults.standard.array(forKey: AlertsModel.dismissedKey) as? [Int64]) ?? [])
    var showDismissed = false
    var unread: Int { unreadRows.count }
    /// An unread alert has severity 2 (critical): the sidebar badge turns prominent.
    var hasUnreadCritical: Bool { unreadRows.contains { $0.severity == 2 } }
    var unreadIDs: Set<Int64> { Set(unreadRows.map(\.id)) }
    /// The newest unread alert: the menu bar glyph and the popover's top line.
    var latestUnread: EventMark? { unreadRows.first }
    private var unreadRows: [EventMark] { alerts.filter { $0.id > readThrough && !dismissed.contains($0.id) } }
    private(set) var error: String?
    /// Rows up to this id were offered to `onNew`.
    private var notifiedThrough = UserDefaults.standard.object(forKey: AlertsModel.notifiedKey) as? Int64 ?? 0 {
        didSet { UserDefaults.standard.set(notifiedThrough, forKey: Self.notifiedKey) }
    }
    /// New rows to notify, oldest first: only those under 10 min old (M4-D8).
    var onNew: (([EventMark]) -> Void)?
    /// Alerts is selected in an active window, so someone can see it: rows that arrive are read at once.
    var shown = false
    /// The rules `amxd` applies, for the span of a revealed alert; their defaults until read or while it is unreachable.
    private(set) var rules = AlertRules()

    private let client: DaemonClient
    private let history: HistoryModel

    init(client: DaemonClient, history: HistoryModel) { (self.client, self.history) = (client, history) }

    func run() async {
        await refreshRules()
        var loaded = false
        while !Task.isCancelled {
            do {
                if loaded { try await poll() } else { try await load(); loaded = true }
                error = nil
            } catch {
                // Once per distinct failure, not every 15 s while the database is missing.
                let message = error.localizedDescription
                if message != self.error { Self.log.error("alerts read failed: \(message, privacy: .public)") }
                self.error = message
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func dismiss(_ ids: Set<Int64>) {
        ids.sorted().forEach { dismissed.insert($0) }
        UserDefaults.standard.set(dismissed.ids, forKey: Self.dismissedKey)
    }

    /// The rows the Alerts screen lists for `search` (by app or message); dismissed rows only while shown.
    func listed(search: String) -> [EventMark] {
        alerts.filter { event in
            (showDismissed || !dismissed.contains(event.id))
                && (search.isEmpty || event.subject.localizedStandardContains(search) || event.message.localizedStandardContains(search)
                    || event.app.map { AppSearch.matches($0, search) } == true)
        }
    }

    /// The listed rows that are not dismissed: Dismiss All dismisses them.
    func undismissed(search: String) -> Set<Int64> {
        Set(listed(search: search).map(\.id).filter { !dismissed.contains($0) })
    }

    func restore(_ ids: Set<Int64>) {
        ids.forEach { dismissed.remove($0) }
        UserDefaults.standard.set(dismissed.ids, forKey: Self.dismissedKey)
    }

    func markAllRead() {
        if let newest = alerts.first?.id, newest > readThrough { readThrough = newest }
    }

    /// At launch, and after Settings changes them.
    func refreshRules() async {
        do { rules = try await client.settings().rules } catch {
            Self.log.error("settings read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() async throws {
        let pool = try history.openPool()
        let (rows, latest) = try await Task.detached {
            let reader = HistoryReader(pool: pool)
            return (try reader.alerts(limit: Self.limit), try reader.latestEventID())
        }.value
        alerts = rows
        // First launch starts with nothing unread; a recreated database restarts the ids.
        if UserDefaults.standard.object(forKey: Self.readKey) == nil || latest < readThrough { readThrough = latest }
        if UserDefaults.standard.object(forKey: Self.notifiedKey) == nil || latest < notifiedThrough { notifiedThrough = latest }
        if shown { markAllRead() }
        let notified = notify(rows.reversed())
        Self.log.debug("alerts load: \(rows.count) rows, \(notified) to notify, \(self.unread) unread, read through \(self.readThrough)")
    }

    private func poll() async throws {
        let pool = try history.openPool()
        let after = alerts.first?.id ?? readThrough
        let new = try await Task.detached { try HistoryReader(pool: pool).alerts(after: after) }.value
        if !new.isEmpty {
            alerts = Array((new.reversed() + alerts).prefix(Self.limit))
            if shown { markAllRead() }
        }
        let notified = notify(new)
        Self.log.debug("alerts poll: \(new.count) new, \(notified) to notify, \(self.unread) unread, after id \(after)")
    }

    /// Offers the fresh rows of `new` (oldest first) to `onNew` and moves `notifiedThrough` past all of them.
    private func notify(_ new: [EventMark]) -> Int {
        let fresh = EventMark.toNotify(new, after: notifiedThrough, now: Date().timeIntervalSince1970)
        if let newest = new.last?.id, newest > notifiedThrough { notifiedThrough = newest }
        if !fresh.isEmpty { onNew?(fresh) }
        return fresh.count
    }
}

extension EventMark {
    /// Who an alert is about: the system for pressure, thermal, CPU, swap and free space rows, else the app. Notification
    /// titles and the Alerts App column.
    var subject: String {
        switch rule {
        case RuleName.pressure: "Memory Pressure"
        case RuleName.thermal: "Thermal"
        case RuleName.systemCPU: "CPU"
        case RuleName.swap: "Swap"
        case RuleName.freeSpace: "Startup Disk"
        default: app?.name ?? "Alert"
        }
    }
}
