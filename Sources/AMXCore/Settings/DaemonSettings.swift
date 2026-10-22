import Foundation
import os

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

/// The facts a preset and the scaled ranges read.
public struct Machine: Sendable {
    public var cores: Int
    public var memoryBytes: UInt64
    public var bootVolumeBytes: UInt64

    /// `hw.ncpu`, `hw.memsize` and the size of the volume at "/" (0 when `statfs` fails, so free space never alerts).
    public static let current: Machine = {
        var fs = statfs()
        if statfs("/", &fs) != 0 {
            Logger(subsystem: AMX.daemonLabel, category: "settings")
                .error("statfs / failed: \(String(cString: strerror(errno)), privacy: .public)")
        }
        return Machine(cores: ProcessInfo.processInfo.processorCount, memoryBytes: ProcessInfo.processInfo.physicalMemory,
                       bootVolumeBytes: UInt64(fs.f_blocks) * UInt64(fs.f_bsize))
    }()

    /// RAM in MB (2^20 bytes, as the memory rules).
    var megabytes: Int { Int(memoryBytes >> 20) }
}

/// Custom is any set of values the user edited; the others compute values for a `Machine` (spec §9).
public enum AlertPreset: String, Codable, Sendable, CaseIterable {
    case relaxed, balanced, strict, custom
}

/// Alert thresholds. Each rule can be switched off. Bytes are binary (MB = 2^20), as the memory rules and alert texts.
public struct AlertRules: Codable, Sendable, Equatable {
    public struct SustainedCPU: Codable, Sendable, Equatable {
        public var enabled = true
        /// Of one core.
        public var percent = 80.0
        public var minutes = 5
        public static let minutesRange = 1...60
        /// Up to all cores, and never narrower than the fixed range of earlier builds.
        public static func percentRange(_ m: Machine) -> ClosedRange<Double> { 10...max(1000, 100 * Double(m.cores)) }
        public init() {}
    }

    public struct MemoryGrowth: Codable, Sendable, Equatable {
        public var enabled = true
        public var minutes = 30
        public var megabytes = 200
        public static let minutesRange = 10...120
        public static func megabytesRange(_ m: Machine) -> ClosedRange<Int> { 50...max(16384, m.megabytes) }
        public init() {}
    }

    public struct MemoryJump: Codable, Sendable, Equatable {
        public var enabled = true
        public var megabytes = 1024
        public static func megabytesRange(_ m: Machine) -> ClosedRange<Int> { 128...max(16384, m.megabytes) }
        public init() {}
    }

    public struct Pressure: Codable, Sendable, Equatable {
        public enum Level: String, Codable, Sendable, CaseIterable {
            case warning, critical

            public var severity: Int { self == .warning ? 1 : 2 }
        }

        public var enabled = true
        public var level = Level.warning
        public init() {}
    }

    public struct Thermal: Codable, Sendable, Equatable {
        public enum State: String, Codable, Sendable, CaseIterable {
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
        public static let minutesRange = 1...60
        public init() {}
    }

    /// An app's writes over the last hour.
    public struct DiskWrites: Codable, Sendable, Equatable {
        public var enabled = true
        public var bytesPerHour: Int64 = 20 << 30
        public static let bytesPerHourRange: ClosedRange<Int64> = (1 << 30)...(1000 << 30)
        public init() {}
    }

    /// An app's bytes in plus out, held.
    public struct Network: Codable, Sendable, Equatable {
        public var enabled = true
        public var bytesPerSecond: Int64 = 10 << 20
        public var minutes = 5
        public static let bytesPerSecondRange: ClosedRange<Int64> = (1 << 20)...(10_000 << 20), minutesRange = 1...60
        public init() {}
    }

    /// The sampler's energy impact (CPU % of one core plus wakeups per second × 0.1), held.
    public struct Energy: Codable, Sendable, Equatable {
        public var enabled = true
        public var impact = 300
        public var minutes = 10
        public static let impactRange = 10...5000, minutesRange = 1...60
        public init() {}
    }

    /// Of one GPU, held.
    public struct GPU: Codable, Sendable, Equatable {
        public var enabled = true
        public var percent = 50
        public var minutes = 5
        public static let percentRange = 10...100, minutesRange = 1...60
        public init() {}
    }

    public struct Swap: Codable, Sendable, Equatable {
        public var enabled = true
        public var percentOfMemory = 50
        public static let percentOfMemoryRange = 10...200
        public init() {}
    }

    /// Of the boot volume; purgeable space does not count as free.
    public struct FreeSpace: Codable, Sendable, Equatable {
        public var enabled = true
        public var percentFree = 10
        public static let percentFreeRange = 1...50
        public init() {}
    }

    /// These fixed values are Custom; `DaemonSettings` starts from `make(.balanced, for: .current)`.
    public var preset = AlertPreset.custom
    public var sustainedCPU = SustainedCPU()
    public var memoryGrowth = MemoryGrowth()
    public var memoryJump = MemoryJump()
    public var pressure = Pressure()
    public var thermal = Thermal()
    public var diskWrites = DiskWrites()
    public var network = Network()
    public var energy = Energy()
    public var gpu = GPU()
    public var swap = Swap()
    public var freeSpace = FreeSpace()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case preset, sustainedCPU = "sustained_cpu", memoryGrowth = "memory_growth", memoryJump = "memory_jump", pressure, thermal
        case diskWrites = "disk_writes", network, energy, gpu, swap, freeSpace = "free_space"
    }

    /// The spec §9 values for `machine` over `base`, whose on/off switches are kept (a preset sets thresholds only;
    /// `AlertRules()` has every rule on). CPU is a share of all cores (stored of one core); memory a share of RAM.
    public static func make(_ preset: AlertPreset, for machine: Machine, keepingSwitchesOf base: AlertRules = AlertRules()) -> AlertRules {
        guard let i = [AlertPreset.relaxed, .balanced, .strict].firstIndex(of: preset) else {
            preconditionFailure("Custom has no values of its own")
        }
        /// Relaxed, Balanced, Strict.
        func pick<T>(_ values: T...) -> T { values[i] }
        func ram(_ percent: Double) -> Int { Int((Double(machine.memoryBytes) * percent / 100 / 1_048_576).rounded()) }
        var r = base
        r.preset = preset
        r.sustainedCPU.percent = pick(50.0, 25, 12) * Double(machine.cores)
        r.sustainedCPU.minutes = pick(10, 5, 3)
        r.memoryGrowth.minutes = 30
        r.memoryGrowth.megabytes = ram(pick(5, 2.5, 1.25))
        r.memoryJump.megabytes = ram(pick(12, 6, 3))
        r.pressure.level = pick(.critical, .warning, .warning)
        r.thermal.state = pick(.critical, .serious, .serious)
        r.thermal.minutes = pick(5, 5, 2)
        r.diskWrites.bytesPerHour = Int64(pick(50, 20, 10)) << 30
        r.network.bytesPerSecond = Int64(pick(50, 10, 2)) << 20
        r.network.minutes = 5
        r.energy.impact = pick(500, 300, 150)
        r.energy.minutes = 10
        r.gpu.percent = pick(80, 50, 30)
        r.gpu.minutes = 5
        r.swap.percentOfMemory = pick(100, 50, 25)
        r.freeSpace.percentFree = pick(5, 10, 15)
        return r
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
    public static let sizeCapRange: ClosedRange<Int64> = 1_000_000_000...50_000_000_000
    /// The Settings picker's choices: 1, 2, 5, 10, 20 and 50 GB (decimal, as `sizeCapBytes`).
    public static let sizeCapChoices: [Int64] = [1, 2, 5, 10, 20, 50].map { $0 * 1_000_000_000 }
    public var terminalBundleIDs = AppAttribution.defaultTerminalBundleIDs.sorted()
    /// A new install (no file) gets Balanced for this Mac.
    public var rules = AlertRules.make(.balanced, for: .current)

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
            // A file without a preset keeps its values as Custom.
            var base = DaemonSettings()
            base.rules.preset = .custom
            let defaults = try JSONSerialization.jsonObject(with: base.encoded()) as? [String: Any] ?? [:]
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

    /// The first problem, or nil when every value is in range for `machine`.
    public func validationProblem(for machine: Machine = .current) -> String? {
        typealias R = AlertRules
        let cpu = R.SustainedCPU.percentRange(machine), growth = R.MemoryGrowth.megabytesRange(machine),
            jump = R.MemoryJump.megabytesRange(machine)
        let checks: [(Bool, String)] = [
            (Self.sizeCapRange.contains(sizeCapBytes), "Size cap must be 1 to 50 GB"),
            (!terminalBundleIDs.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "A terminal bundle ID is empty"),
            (terminalBundleIDs.count <= 32, "Use at most 32 terminal apps"),
            (cpu.contains(rules.sustainedCPU.percent), "Sustained CPU must be 10 to \(Int(cpu.upperBound)) %"),
            (R.SustainedCPU.minutesRange.contains(rules.sustainedCPU.minutes), "Sustained CPU time must be 1 to 60 min"),
            (R.MemoryGrowth.minutesRange.contains(rules.memoryGrowth.minutes), "Memory growth time must be 10 to 120 min"),
            (growth.contains(rules.memoryGrowth.megabytes), "Memory growth must be 50 to \(growth.upperBound) MB"),
            (jump.contains(rules.memoryJump.megabytes), "Memory jump must be 128 to \(jump.upperBound) MB"),
            (R.Thermal.minutesRange.contains(rules.thermal.minutes), "Thermal time must be 1 to 60 min"),
            (R.DiskWrites.bytesPerHourRange.contains(rules.diskWrites.bytesPerHour), "Disk writes must be 1 to 1000 GB per hour"),
            (R.Network.bytesPerSecondRange.contains(rules.network.bytesPerSecond), "Network must be 1 to 10000 MB/s"),
            (R.Network.minutesRange.contains(rules.network.minutes), "Network time must be 1 to 60 min"),
            (R.Energy.impactRange.contains(rules.energy.impact), "Energy impact must be 10 to 5000"),
            (R.Energy.minutesRange.contains(rules.energy.minutes), "Energy time must be 1 to 60 min"),
            (R.GPU.percentRange.contains(rules.gpu.percent), "GPU must be 10 to 100 %"),
            (R.GPU.minutesRange.contains(rules.gpu.minutes), "GPU time must be 1 to 60 min"),
            (R.Swap.percentOfMemoryRange.contains(rules.swap.percentOfMemory), "Swap must be 10 to 200 % of memory"),
            (R.FreeSpace.percentFreeRange.contains(rules.freeSpace.percentFree), "Free space must be 1 to 50 %"),
        ]
        return checks.first { !$0.0 }?.1
    }

    /// Adds the bundle ID of the `.app` at `url` to the terminal list; a duplicate changes nothing.
    public mutating func addTerminal(appAt url: URL) throws {
        guard let id = AppAttribution.bundleID(inApp: url.path) else {
            throw SettingsError.invalid("\(url.lastPathComponent) has no bundle ID")
        }
        if !terminalBundleIDs.contains(id) { terminalBundleIDs.append(id) }
    }
}
