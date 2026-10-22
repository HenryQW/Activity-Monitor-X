import AMXCore
import Foundation
import os

/// Listener delegate and exported object. Immutable after init, so concurrent connections are safe.
final class XPCService: NSObject, NSXPCListenerDelegate, DaemonXPC, @unchecked Sendable {
    /// Settings bodies are under 2 KB; the cap bounds decoding work on untrusted input.
    private static let maxSettingsBytes = 64 * 1024

    private let dbPath: String
    private let liveSnapshot: @Sendable () -> Data?
    private let currentSettings: @Sendable () -> Data
    private let applySettings: @Sendable (Data) -> String?
    private let started = ProcessInfo.processInfo.systemUptime
    private let requirement: String?
    private let log = Logger(subsystem: AMX.daemonLabel, category: "xpc")

    /// The closures run on the daemon queue. `setSettings` replies nil when it saved and applied `json`.
    init(dbPath: String, live: @escaping @Sendable () -> Data?, settings: @escaping @Sendable () -> Data,
         setSettings: @escaping @Sendable (Data) -> String?) {
        self.dbPath = dbPath
        liveSnapshot = live
        currentSettings = settings
        applySettings = setSettings
        requirement = SigningRequirement.ownLeafSHA1().map { SigningRequirement.string(leafSHA1Hex: $0) }
        super.init()
        if requirement == nil {
            log.error("amxd has no leaf signing certificate (unsigned or ad-hoc); refusing all XPC connections")
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Fail closed: without our own leaf hash there is nothing to pin callers to.
        guard let requirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: DaemonXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func ping(reply: @escaping (String) -> Void) {
        let info = DaemonPing(version: DaemonPing.protocolVersion,
                              uptime: Int(ProcessInfo.processInfo.systemUptime - started), db: dbPath, pid: getpid())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        reply(String(decoding: try! encoder.encode(info), as: UTF8.self))
    }

    func signal(pid: Int32, startTime: Double, signal: Int32, reply: @escaping (Int32) -> Void) {
        let caller = NSXPCConnection.current()?.processIdentifier ?? -1
        var refused = SignalPolicy.checkIdentity(pid: pid, startTime: startTime)
        if refused == 0 { refused = SignalPolicy.check(pid: pid, signal: signal, selfPID: getpid()) }
        guard refused == 0 else {
            log.error("signal \(signal, privacy: .public) to pid \(pid, privacy: .public) refused \(refused, privacy: .public) (caller \(caller, privacy: .public))")
            reply(refused)
            return
        }
        let result = kill(pid, signal) == 0 ? 0 : errno
        log.notice("signal \(signal, privacy: .public) to pid \(pid, privacy: .public) by caller \(caller, privacy: .public): \(result, privacy: .public)")
        reply(result)
    }

    func live(reply: @escaping (Data?) -> Void) {
        reply(liveSnapshot())
    }

    func settings(reply: @escaping (Data) -> Void) {
        reply(currentSettings())
    }

    func setSettings(_ json: Data, reply: @escaping (String?) -> Void) {
        let caller = NSXPCConnection.current()?.processIdentifier ?? -1
        let problem = json.count > Self.maxSettingsBytes ? "Settings are larger than 64 KB" : applySettings(json)
        if let problem {
            log.error("setSettings by caller \(caller, privacy: .public) refused: \(problem, privacy: .public)")
        } else {
            log.notice("setSettings by caller \(caller, privacy: .public): saved and applied")
        }
        reply(problem)
    }
}
