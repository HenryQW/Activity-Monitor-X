import GRDB

public struct ProcessRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "processes"
    public var id: Int64?
    public var pid: Int32
    public var startTime: Double
    public var name: String
    public var path: String?
    public var appPath: String?
    public var appName: String?
    public var bundleId: String?
    public var teamId: String?
    public var uid: Int64?
    public var translated: Bool
    public var firstSeen: Double
    public var lastSeen: Double

    enum CodingKeys: String, CodingKey {
        case id, pid, name, path, uid, translated
        case startTime = "start_time", appPath = "app_path", appName = "app_name"
        case bundleId = "bundle_id", teamId = "team_id", firstSeen = "first_seen", lastSeen = "last_seen"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ProcessSampleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "process_samples"
    public var processId: Int64
    public var ts: Double
    public var cpu: Double?
    public var mem: Int64?
    public var diskR: Double?
    public var diskW: Double?
    public var energy: Double?
    public var gpu: Double?
    public var netIn: Double?
    public var netOut: Double?

    enum CodingKeys: String, CodingKey {
        case ts, cpu, mem, energy, gpu
        case processId = "process_id", diskR = "disk_r", diskW = "disk_w", netIn = "net_in", netOut = "net_out"
    }
}

public struct SystemSampleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "system_samples"
    public var ts: Double
    public var cpu: Double?
    public var memUsed: Int64?
    public var memCompressed: Int64?
    public var swapUsed: Int64?
    public var pressureLevel: Int64?
    public var pressurePct: Double?
    public var thermalState: Int64?
    public var load1: Double?
    public var diskR: Double?
    public var diskW: Double?
    public var diskIops: Double?
    public var diskLatMs: Double?
    public var diskUtil: Double?
    public var gpu: Double?
    public var tempCpu: Double?
    public var tempGpu: Double?
    public var tempSsd: Double?
    public var netIn: Double?
    public var netOut: Double?

    enum CodingKeys: String, CodingKey {
        case ts, cpu, load1, gpu
        case memUsed = "mem_used", memCompressed = "mem_compressed", swapUsed = "swap_used"
        case pressureLevel = "pressure_level", pressurePct = "pressure_pct", thermalState = "thermal_state"
        case diskR = "disk_r", diskW = "disk_w", diskIops = "disk_iops", diskLatMs = "disk_lat_ms"
        case diskUtil = "disk_util", tempCpu = "temp_cpu", tempGpu = "temp_gpu", tempSsd = "temp_ssd"
        case netIn = "net_in", netOut = "net_out"
    }
}

public struct EventRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "events"
    public var id: Int64?
    public var ts: Double
    public var kind: String
    public var severity: Int
    public var processId: Int64?
    public var rule: String?
    public var message: String
    public var value: Double?

    enum CodingKeys: String, CodingKey {
        case id, ts, kind, severity, rule, message, value
        case processId = "process_id"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct MetaRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "meta"
    public var key: String
    public var value: Double
}
