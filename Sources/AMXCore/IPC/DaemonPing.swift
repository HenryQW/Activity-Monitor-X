import Foundation

/// `ping` reply. Version 1 had the same keys; version 2 adds `settings` and `setSettings`;
/// version 3 refuses to signal a process of another user; version 4 applies per-app alert rules;
/// version 5 adds `openFiles`.
public struct DaemonPing: Codable, Sendable, Equatable {
    public static let protocolVersion = 5

    public let version: Int
    public let uptime: Int
    public let db: String
    public let pid: Int32

    public init(version: Int, uptime: Int, db: String, pid: Int32) {
        self.version = version
        self.uptime = uptime
        self.db = db
        self.pid = pid
    }
}
