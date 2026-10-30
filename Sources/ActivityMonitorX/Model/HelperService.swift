import AMXCore
import AppKit
import Observation
import os
import ServiceManagement

/// The helper bundled in the app, registered with launchd through `SMAppService` (D91). Nil service outside the
/// release bundle in /Applications: dev builds, `swift run` and the `.build` copy leave the installed helper alone.
@Observable @MainActor
final class HelperService {
    private static let log = Logger(subsystem: AMX.bundleID, category: "helper")
    private static let service = Bundle.main.bundleIdentifier == AMX.bundleID && Bundle.main.bundlePath.hasPrefix("/Applications/")
        ? SMAppService.daemon(plistName: "\(AMX.daemonLabel).plist") : nil

    /// Registered, but Login Items waits for the owner to allow the helper.
    private(set) var needsApproval = false

    init() {
        if Self.service == nil { Self.log.notice("helper registration off: not running from the app bundle") }
        // The owner allows the helper in System Settings, then comes back to the app.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Registers a helper that is not registered. With a self-signed app, the first `register` throws "Operation not
    /// permitted" and leaves `requiresApproval`: the expected first run, not a failure.
    func register() {
        guard let service = Self.service else { return }
        // A never-registered service can read `notFound`, not `notRegistered` (Task 0 probe 6).
        if [.notRegistered, .notFound].contains(service.status) {
            do { try service.register() } catch {
                Self.log.notice("helper register: \(error.localizedDescription, privacy: .public)")
            }
        }
        refresh()
    }

    func refresh() {
        needsApproval = Self.service?.status == .requiresApproval
    }
}
