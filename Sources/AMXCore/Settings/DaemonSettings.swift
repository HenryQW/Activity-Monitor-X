import Foundation

public enum SettingsError: LocalizedError, CustomStringConvertible, Equatable {
    case unsupportedVersion(Int)
    case invalid(String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let found): "settings.json has version \(found); this build reads version 1"
        case .invalid(let problem): problem
        }
    }

    public var errorDescription: String? { description }
}

/// Alert thresholds. Each rule can be switched off.
public struct AlertRules: Codable, Sendable, Equatable {
    public struct SustainedCPU: Codable, Sendable, Equatable {
        public var enabled = true
        /// Of one core.
        public var percent = 80.0
        public var minutes = 5
        public init() {}
    }

    public struct MemoryGrowth: Codable, Sendable, Equatable {
        public var enabled = true
        public var minutes = 30
        public var megabytes = 200
        public init() {}
    }

    public struct MemoryJump: Codable, Sendable, Equatable {
        public var enabled = true
        public var megabytes = 1024
        public init() {}
    }

    public struct Pressure: Codable, Sendable, Equatable {
        public enum Level: String, Codable, Sendable {
            case warning, critical

            public var severity: Int { self == .warning ? 1 : 2 }
        }

        public var enabled = true
        public var level = Level.warning
        public init() {}
    }

    public struct Thermal: Codable, Sendable, Equatable {
        public enum State: String, Codable, Sendable {
            case fair, serious, critical

            /// `ProcessInfo.ThermalState` raw value.
            public var rawState: Int {
                switch self {
                case .fair: 1
                case .serious: 2
                case .critical: 3
                }
            }
        }

        public var enabled = true
        public var state = State.serious
        public var minutes = 5
        public init() {}
    }

    public var sustainedCPU = SustainedCPU()
    public var memoryGrowth = MemoryGrowth()
    public var memoryJump = MemoryJump()
    public var pressure = Pressure()
    public var thermal = Thermal()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case sustainedCPU = "sustained_cpu", memoryGrowth = "memory_growth", memoryJump = "memory_jump", pressure, thermal
    }
}

/// `settings.json`: `{"version":1,"settings":{…}}`. Only `amxd` writes it; the app changes it over XPC.
public struct DaemonSettings: Codable, Sendable, Equatable {
    private static let version = 1

    private struct Version: Decodable { let version: Int }
    private struct File: Codable {
        let version: Int
        let settings: DaemonSettings
    }

    public var sizeCapBytes: Int64 = 2_000_000_000
    public var terminalBundleIDs = AppAttribution.defaultTerminalBundleIDs.sorted()
    public var rules = AlertRules()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case sizeCapBytes = "size_cap_bytes", terminalBundleIDs = "terminal_bundle_ids", rules
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(version: Self.version, settings: self))
    }

    /// Keys missing from the file take their defaults, so a file written by an older build still loads.
    public static func decodeValidated(_ data: Data) throws -> DaemonSettings {
        do {
            let found = try JSONDecoder().decode(Version.self, from: data).version
            guard found == version else { throw SettingsError.unsupportedVersion(found) }
            let defaults = try JSONSerialization.jsonObject(with: DaemonSettings().encoded()) as? [String: Any] ?? [:]
            let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let merged = try JSONSerialization.data(withJSONObject: merge(defaults, stored))
            let settings = try JSONDecoder().decode(File.self, from: merged).settings
            if let problem = settings.validationProblem() { throw SettingsError.invalid(problem) }
            return settings
        } catch let error as DecodingError {
            let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "unreadable"
            throw SettingsError.invalid("settings.json: \(reason)")
        }
    }

    private static func merge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        base.merging(over) { old, new in
            if let old = old as? [String: Any], let new = new as? [String: Any] { merge(old, new) } else { new }
        }
    }

    /// A missing file gives the defaults.
    public static func load(from url: URL) throws -> DaemonSettings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return DaemonSettings()
        }
        return try decodeValidated(data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    /// The first problem, or nil when every value is in range.
    public func validationProblem() -> String? {
        let checks: [(Bool, String)] = [
            ((1_000_000_000...50_000_000_000).contains(sizeCapBytes), "Size cap must be 1 to 50 GB"),
            (!terminalBundleIDs.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "A terminal bundle ID is empty"),
            (terminalBundleIDs.count <= 32, "Use at most 32 terminal apps"),
            ((10.0...1000).contains(rules.sustainedCPU.percent), "Sustained CPU must be 10 to 1000 %"),
            ((1...60).contains(rules.sustainedCPU.minutes), "Sustained CPU time must be 1 to 60 min"),
            ((10...120).contains(rules.memoryGrowth.minutes), "Memory growth time must be 10 to 120 min"),
            ((50...16384).contains(rules.memoryGrowth.megabytes), "Memory growth must be 50 to 16384 MB"),
            ((256...16384).contains(rules.memoryJump.megabytes), "Memory jump must be 256 to 16384 MB"),
            ((1...60).contains(rules.thermal.minutes), "Thermal time must be 1 to 60 min"),
        ]
        return checks.first { !$0.0 }?.1
    }
}
