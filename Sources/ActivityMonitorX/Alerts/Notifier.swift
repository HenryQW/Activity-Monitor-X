import AMXCore
import Observation
import os
import UserNotifications

/// Posts one notification per new alert and opens the app at it (M4-D8, M4-D16). Only inside the app bundle:
/// notifications need a bundle ID that matches the signature.
@Observable @MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "alert", showApps = "show-apps"
    nonisolated private static let log = Logger(subsystem: AMX.bundleID, category: "notifications")

    /// Settings says "Notifications are off" unless authorized; it reads denied while the Allow prompt waits.
    private(set) var status = UNAuthorizationStatus.notDetermined

    private let selection: Selection
    private let history: HistoryModel
    private let alerts: AlertsModel
    private let center = UNUserNotificationCenter.current()

    init(selection: Selection, history: HistoryModel, alerts: AlertsModel) {
        self.selection = selection
        self.history = history
        self.alerts = alerts
        super.init()
        let action = UNNotificationAction(identifier: Self.showApps, title: "Show in Apps", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [action], intentIdentifiers: [])])
    }

    /// The first request waits for the owner's click; later ones return at once (UNErrorDomain 1 when not allowed).
    func authorize() async {
        await refreshStatus()
        do {
            let granted = try await center.requestAuthorization(options: [.alert])
            Self.log.notice("authorization granted: \(granted)")
        } catch {
            let error = error as NSError
            Self.log.notice("authorization: \(error.domain, privacy: .public) \(error.code)")
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
        Self.log.notice("authorization status: \(self.status.rawValue)")
    }

    /// `new` is oldest first. More than 3 give one summary, which opens Alerts.
    func post(_ new: [EventMark]) {
        guard let newest = new.last else { return }
        if new.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "\(new.count) New Alerts"
            content.body = newest.message
            add(content, id: "alerts-\(newest.id)")
            return
        }
        for event in new {
            let content = UNMutableNotificationContent()
            content.title = event.subject
            content.body = event.message
            content.threadIdentifier = event.rule ?? event.kind
            content.userInfo = ["eventID": event.id]
            content.categoryIdentifier = Self.category
            add(content, id: "alert-\(event.id)")
        }
    }

    private func add(_ content: UNMutableNotificationContent, id: String) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error = error as NSError? {
                Self.log.error("add \(id, privacy: .public): \(error.domain, privacy: .public) \(error.code)")
            } else {
                Self.log.notice("add \(id, privacy: .public): ok")
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .list] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let id = response.notification.request.content.userInfo["eventID"] as? Int64
        await open(action: action, eventID: id)
    }

    /// A click opens Alerts; Show in Apps opens Apps at the alert.
    private func open(action: String, eventID: Int64?) async {
        selection.openMain?()
        if action == Self.showApps, let event = alerts.alerts.first(where: { $0.id == eventID }) {
            selection.reveal(event, history: history, rules: alerts.rules)
        } else {
            selection.sidebar = .alerts
        }
    }
}
