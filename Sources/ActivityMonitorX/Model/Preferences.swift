import AMXCore
import Foundation
import Observation
import os
import ServiceManagement

/// App choices kept in the app: the menu bar item (M4-D11) and launch at login.
@Observable @MainActor
final class Preferences {
    private static let menuBarKey = "menuBarShown"
    private static let log = Logger(subsystem: AMX.bundleID, category: "preferences")
    /// Nil outside the app bundle (`swift run`): a login item needs the bundle.
    private static let service = Bundle.main.bundleIdentifier == AMX.bundleID ? SMAppService.mainApp : nil

    /// Shown by default; while shown, closing the window keeps the app running for notifications.
    var menuBarShown = UserDefaults.standard.object(forKey: Preferences.menuBarKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuBarShown, forKey: Self.menuBarKey) }
    }

    /// On while registered, also while Login Items waits for approval. Setting it registers or unregisters.
    var launchAtLogin: Bool {
        get { loginOn }
        set {
            guard let service = Self.service else { return }
            do {
                try newValue ? service.register() : service.unregister()
                loginError = nil
            } catch {
                loginError = error.localizedDescription
                Self.log.error("login item: \(error.localizedDescription, privacy: .public)")
            }
            refreshLogin()
        }
    }
    private(set) var loginError: String?
    /// Registered, but Login Items waits for the owner to allow it.
    private(set) var loginNeedsApproval = false
    private var loginOn = false

    init() {
        if Self.service == nil { Self.log.notice("launch at login off: not running from the app bundle") }
        refreshLogin()
    }

    /// The owner can change it in System Settings; Settings re-reads it when its window gains focus.
    func refreshLogin() {
        guard let service = Self.service else { return }
        // A never-registered app reads `notFound`, not `notRegistered` (Task 0 probe 6).
        loginOn = [.enabled, .requiresApproval].contains(service.status)
        loginNeedsApproval = service.status == .requiresApproval
    }
}
