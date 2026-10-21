import Foundation

/// One 1 s live sample from `amxd`, sent as JSON over XPC (`DaemonXPC.live`). Units match the history DB.
public struct LiveSnapshot: Codable, Sendable, Equatable {
    public let ts: Double
    public let system: LiveSystem
    public let processes: [LiveProcess]

    public init(ts: Double, system: LiveSystem, processes: [LiveProcess]) {
        self.ts = ts
        self.system = system
        self.processes = processes
    }
}

public struct LiveSystem: Codable, Sendable, Equatable {
    public let cpu: Double
    public let memUsed: UInt64
    public let pressureLevel: Int
    public let thermalState: Int

    public init(cpu: Double, memUsed: UInt64, pressureLevel: Int, thermalState: Int) {
        self.cpu = cpu
        self.memUsed = memUsed
        self.pressureLevel = pressureLevel
        self.thermalState = thermalState
    }
}

public struct LiveProcess: Codable, Sendable, Equatable {
    public let pid: Int32
    public let startTime: Double
    public let name: String
    /// App path when present, else the process name.
    public let appKey: String
    /// App name when present, else the process name.
    public let appName: String
    /// Executable path; nil when the daemon could not read it.
    public let path: String?
    public let cpu: Double
    public let mem: UInt64
    public let diskR: Double
    public let diskW: Double
    public let netIn: Double
    public let netOut: Double
    public let gpu: Double
    public let energy: Double
    /// The attributed app's bundle ID and the executable's team ID; nil from an older daemon.
    public let bundleID: String?
    public let teamID: String?

    public init(pid: Int32, startTime: Double, name: String, appKey: String, appName: String, path: String?, cpu: Double,
                mem: UInt64, diskR: Double, diskW: Double, netIn: Double, netOut: Double, gpu: Double,
                energy: Double, bundleID: String? = nil, teamID: String? = nil) {
        self.pid = pid
        self.startTime = startTime
        self.name = name
        self.appKey = appKey
        self.appName = appName
        self.path = path
        self.cpu = cpu
        self.mem = mem
        self.diskR = diskR
        self.diskW = diskW
        self.netIn = netIn
        self.netOut = netOut
        self.gpu = gpu
        self.energy = energy
        self.bundleID = bundleID
        self.teamID = teamID
    }
}

/// Live sampling runs while a client asked within the last 3 s.
public struct LiveDemand: Sendable {
    private var last: Double?

    public init() {}

    public mutating func requested(at now: Double) { last = now }

    public func shouldSample(now: Double) -> Bool { last.map { now - $0 < 3 } ?? false }
}
