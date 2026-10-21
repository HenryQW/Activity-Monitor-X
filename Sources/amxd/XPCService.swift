import AMXCore
import Foundation
import os

/// Listener delegate and exported object. Immutable after init, so concurrent connections are safe.
final class XPCService: NSObject, NSXPCListenerDelegate, DaemonXPC, @unchecked Sendable {
    private struct Ping: Encodable {
        let version = 1
        let uptime: Int
        let db: String
        let pid: Int32
    }

    private let dbPath: String
    private let started = ProcessInfo.processInfo.systemUptime
    private let requirement: String?
    private let log = Logger(subsystem: AMX.daemonLabel, category: "xpc")

    init(dbPath: String) {
        self.dbPath = dbPath
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
        let info = Ping(uptime: Int(ProcessInfo.processInfo.systemUptime - started), db: dbPath, pid: getpid())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        reply(String(decoding: try! encoder.encode(info), as: UTF8.self))
    }

    func signal(pid: Int32, signal: Int32, reply: @escaping (Int32) -> Void) {
        let caller = NSXPCConnection.current()?.processIdentifier ?? -1
        let refused = SignalPolicy.check(pid: pid, signal: signal, selfPID: getpid())
        guard refused == 0 else {
            log.error("signal \(signal, privacy: .public) to pid \(pid, privacy: .public) refused (caller \(caller, privacy: .public))")
            reply(refused)
            return
        }
        let result = kill(pid, signal) == 0 ? 0 : errno
        log.notice("signal \(signal, privacy: .public) to pid \(pid, privacy: .public) by caller \(caller, privacy: .public): \(result, privacy: .public)")
        reply(result)
    }
}
