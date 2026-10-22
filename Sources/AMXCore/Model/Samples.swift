import Foundation

/// A process incarnation: a reused pid has a different start time.
public struct ProcessIdentity: Hashable, Sendable, Codable {
    public let pid: Int32
    public let startTime: Double

    public init(pid: Int32, startTime: Double) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// Raw cumulative counters for one process at one instant.
public struct RawProcess: Sendable {
    public let identity: ProcessIdentity
    public let name: String
    public let path: String?
    public let uid: UInt32
    public let cpuNanos: UInt64
    public let footprint: UInt64
    public let diskRead: UInt64
    public let diskWritten: UInt64
    public let wakeups: UInt64
    public let translated: Bool

    public init(identity: ProcessIdentity, name: String, path: String?, uid: UInt32,
                cpuNanos: UInt64, footprint: UInt64, diskRead: UInt64, diskWritten: UInt64,
                wakeups: UInt64, translated: Bool) {
        self.identity = identity
        self.name = name
        self.path = path
        self.uid = uid
        self.cpuNanos = cpuNanos
        self.footprint = footprint
        self.diskRead = diskRead
        self.diskWritten = diskWritten
        self.wakeups = wakeups
        self.translated = translated
    }
}

/// Per-second rates for one process over one tick. `cpu` is percent of one core.
public struct ProcessSample: Sendable {
    public let identity: ProcessIdentity
    public let cpu: Double
    public let mem: UInt64
    public let diskR: Double
    public let diskW: Double
    public let energy: Double
    public var gpu: Double
    public var netIn: Double
    public var netOut: Double
}
