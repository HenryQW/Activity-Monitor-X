import Foundation

/// `ping` reply. Version 1 had the same keys; version 2 adds `settings` and `setSettings`;
/// version 3 refuses to signal a process of another user.
public struct DaemonPing: Codable, Sendable, Equatable {
    public static let protocolVersion = 3

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
