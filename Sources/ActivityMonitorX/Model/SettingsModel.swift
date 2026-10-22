import AMXCore
import Observation
import os

/// The daemon's settings for the Settings window (M4-D1): read and changed only over XPC, never from the file.
@Observable @MainActor
final class SettingsModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "settings")

    /// Nil while `amxd` is unreachable or too old; daemon-backed controls are disabled then.
    private(set) var settings: DaemonSettings?
    /// Nil while `amxd` is unreachable.
    private(set) var ping: DaemonPing?
    private(set) var error: String?
    /// Counts changes, so a `load` that started before a change does not show the older values it read.
    private var generation = 0

    private let client: DaemonClient
    private let alerts: AlertsModel

    init(client: DaemonClient, alerts: AlertsModel) {
        self.client = client
        self.alerts = alerts
    }

    /// Pings first: a version 1 helper has no `settings` call.
    func load() async {
        let start = generation
        do {
            let ping: DaemonPing
            do { ping = try await client.ping() } catch {
                self.ping = nil
                Self.log.error("ping failed: \(error.localizedDescription, privacy: .public)")
                throw SettingsError.invalid("The helper is not reachable. See Helper.")
            }
            self.ping = ping
            guard ping.version >= DaemonPing.protocolVersion else { throw SettingsError.invalid("The helper is out of date. See Helper.") }
            let read = try await client.settings()
            guard generation == start else { return }
            settings = read
            error = nil
        } catch {
            settings = nil
            self.error = error.localizedDescription
            Self.log.error("settings load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the change at once and sends it; a problem shows its text, and a refusal also reloads what `amxd` keeps.
    func apply(_ change: (inout DaemonSettings) throws -> Void) async {
        guard var new = settings else { return }
        do {
            try change(&new)
            guard new != settings else { return }
            if let problem = new.validationProblem() { throw SettingsError.invalid(problem) }
        } catch {
            self.error = error.localizedDescription
            return
        }
        settings = new
        generation += 1
        do {
            try await client.setSettings(new)
            error = nil
            // "Show in Apps" spans the rule's own window, so it needs the new values.
            await alerts.refreshRules()
        } catch {
            let message = error.localizedDescription
            Self.log.error("settings change refused: \(message, privacy: .public)")
            await load()
            self.error = message
        }
    }
}
