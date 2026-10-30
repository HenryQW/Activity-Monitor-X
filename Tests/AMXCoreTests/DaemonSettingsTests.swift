import Foundation
import Testing
@testable import AMXCore

@Suite struct DaemonSettingsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("amx-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }

    private func json(_ settings: DaemonSettings) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: settings.encoded()) as? [String: Any])
    }

    @Test func missingFileGivesDefaults() throws {
        #expect(try DaemonSettings.load(from: tempURL()) == DaemonSettings())
    }

    @Test func roundTrip() throws {
        var settings = DaemonSettings()
        settings.sizeCapBytes = 5_000_000_000
        settings.rules.sustainedCPU.percent = 150
        settings.rules.pressure.level = .critical
        let url = tempURL()
        try settings.save(to: url)
        #expect(try DaemonSettings.load(from: url) == settings)
        var own = AlertRules.AppOverride()
        own.muted = true
        own.gpu = AlertRules.GPU()
        settings.rules.apps["/Applications/A.app"] = own
        try settings.save(to: url)
        #expect(try DaemonSettings.load(from: url) == settings)
    }

    @Test func fileShape() throws {
        let top = try json(DaemonSettings())
        #expect(Set(top.keys) == ["settings", "version"])
        #expect(top["version"] as? Int == 1)
        let body = try #require(top["settings"] as? [String: Any])
        #expect(Set(body.keys) == ["rules", "size_cap_bytes", "terminal_bundle_ids"])
        let rules = try #require(body["rules"] as? [String: Any])
        #expect(Set(rules.keys) == ["disk_writes", "energy", "free_space", "gpu", "memory_growth", "memory_jump", "network",
                                    "preset", "pressure", "sustained_cpu", "swap", "system_cpu", "thermal", "apps"])
        #expect(rules["preset"] as? String == "balanced")
        let pressure = try #require(rules["pressure"] as? [String: Any])
        #expect(pressure["level"] as? String == "warning")
    }

    @Test func missingKeysTakeDefaults() throws {
        let data = Data(#"{"version":1,"settings":{"size_cap_bytes":5000000000,"rules":{"pressure":{"level":"critical"}}}}"#.utf8)
        var expected = DaemonSettings()
        expected.sizeCapBytes = 5_000_000_000
        expected.rules.pressure.level = .critical
        expected.rules.preset = .custom
        #expect(try DaemonSettings.decodeValidated(data) == expected)
    }

    @Test func oldSettingsDecodeAsCustom() throws {
        // Every field an earlier build wrote, none of them a Balanced value.
        let data = Data(#"""
            {"version":1,"settings":{"size_cap_bytes":2000000000,"terminal_bundle_ids":["com.apple.Terminal"],"rules":{
            "sustained_cpu":{"enabled":true,"percent":80,"minutes":5},
            "memory_growth":{"enabled":false,"minutes":30,"megabytes":200},
            "memory_jump":{"enabled":true,"megabytes":1024},
            "pressure":{"enabled":true,"level":"critical"},
            "thermal":{"enabled":true,"state":"fair","minutes":7}}}}
            """#.utf8)
        let rules = try DaemonSettings.decodeValidated(data).rules
        var expected = DaemonSettings().rules
        expected.preset = .custom
        expected.sustainedCPU = AlertRules.SustainedCPU()
        expected.memoryGrowth = AlertRules.MemoryGrowth()
        expected.memoryGrowth.enabled = false
        expected.memoryJump = AlertRules.MemoryJump()
        expected.pressure.level = .critical
        expected.thermal.state = .fair
        expected.thermal.minutes = 7
        #expect(rules == expected)
    }

    @Test(arguments: ["-1e400", "1e400"])
    func numberOutOfRangeThrowsSettingsError(number: String) {
        let data = Data(#"{"version":1,"settings":{"rules":{"sustained_cpu":{"percent":\#(number)}}}}"#.utf8)
        #expect(throws: SettingsError.invalid("settings.json: Number \(number) is not representable in Swift.")) {
            try DaemonSettings.decodeValidated(data)
        }
    }

    /// The old binary maximums, 1000 GiB per hour and 10000 MiB/s, are above the decimal ones (D88): they clamp, so the
    /// file still loads.
    @Test func oldBinaryMaximumsClamp() throws {
        let data = Data(#"""
            {"version":1,"settings":{"rules":{"disk_writes":{"bytesPerHour":1073741824000},
            "network":{"bytesPerSecond":10485760000}}}}
            """#.utf8)
        let rules = try DaemonSettings.decodeValidated(data).rules
        #expect(rules.diskWrites.bytesPerHour == 1_000_000_000_000 && rules.network.bytesPerSecond == 10_000_000_000)
    }

    @Test func missingFieldKeepsTheOtherValues() throws {
        let data = Data(#"""
            {"version":1,"settings":{"size_cap_bytes":5000000000,"rules":{"preset":"strict",
            "sustained_cpu":{"enabled":false,"percent":150},
            "apps":{"/Applications/A.app":{"gpu":{"percent":30}},"/Applications/B.app":{"muted":true}}}}}
            """#.utf8)
        let settings = try DaemonSettings.decodeValidated(data)
        #expect(settings.sizeCapBytes == 5_000_000_000 && settings.rules.preset == .strict)
        var cpu = AlertRules.SustainedCPU()
        cpu.enabled = false
        cpu.percent = 150
        #expect(settings.rules.sustainedCPU == cpu)
        // A rule the file lacks takes the preset's value.
        #expect(settings.rules.gpu == AlertRules.make(.strict, for: .current).gpu)
        #expect(settings.rules.systemCPU == AlertRules.make(.strict, for: .current).systemCPU)
        var gpu = AlertRules.GPU()
        gpu.percent = 30
        var a = AlertRules.AppOverride()
        a.gpu = gpu
        var b = AlertRules.AppOverride()
        b.muted = true
        #expect(settings.rules.apps == ["/Applications/A.app": a, "/Applications/B.app": b])
    }

    @Test func presetsValidOnSmallAndLargeMacs() {
        let small = Machine(cores: 8, memoryBytes: 8 << 30, bootVolumeBytes: 256_000_000_000)
        let large = Machine(cores: 24, memoryBytes: 192 << 30, bootVolumeBytes: 8_000_000_000_000)
        for machine in [small, large] {
            for preset in [AlertPreset.relaxed, .balanced, .strict] {
                var settings = DaemonSettings()
                settings.rules = .make(preset, for: machine)
                #expect(settings.rules.preset == preset)
                #expect(settings.validationProblem(for: machine) == nil, "\(preset) on \(machine.cores) cores")
            }
        }
        // Stricter presets alert sooner: 50, 25 and 12 % of 8 cores; 12, 6 and 3 % of 8 GB.
        let rules = [AlertPreset.relaxed, .balanced, .strict].map { AlertRules.make($0, for: small) }
        #expect(rules.map(\.sustainedCPU.percent) == [400, 200, 96])
        #expect(rules.map(\.memoryJump.megabytes) == [983, 492, 246])
        #expect(rules.map(\.diskWrites.bytesPerHour) == [50_000_000_000, 20_000_000_000, 10_000_000_000])
        #expect(rules.map(\.freeSpace.percentFree) == [5, 10, 15])
    }

    @Test func presetKeepsSwitches() {
        var base = AlertRules()
        base.gpu.enabled = false
        base.energy.minutes = 60
        let rules = AlertRules.make(.strict, for: Machine(cores: 8, memoryBytes: 8 << 30, bootVolumeBytes: 1 << 40),
                                    keepingSwitchesOf: base)
        #expect(!rules.gpu.enabled && rules.sustainedCPU.enabled)
        #expect(rules.gpu.percent == 30 && rules.energy.minutes == 10)
    }

    @Test func balancedOn15Cores48GB() {
        let rules = AlertRules.make(.balanced, for: Machine(cores: 15, memoryBytes: 48 << 30, bootVolumeBytes: 1 << 40))
        #expect(rules.sustainedCPU.percent == 375 && rules.sustainedCPU.minutes == 5)
        #expect(rules.memoryGrowth.megabytes == 1229 && rules.memoryGrowth.minutes == 30)  // 1.2 GB
        #expect(rules.memoryJump.megabytes == 2949)  // 2.9 GB
        #expect(rules.pressure.level == .warning && rules.thermal.state == .serious && rules.thermal.minutes == 5)
        #expect(rules.diskWrites.bytesPerHour == 20_000_000_000)
        #expect(rules.network.bytesPerSecond == 10_000_000 && rules.network.minutes == 5)
        #expect(rules.energy.impact == 300 && rules.energy.minutes == 10)
        #expect(rules.gpu.percent == 50 && rules.gpu.minutes == 5)
        #expect(rules.swap.percentOfMemory == 50 && rules.freeSpace.percentFree == 10)
    }

    @Test func unknownEnumValueThrowsSettingsError() {
        let data = Data(#"{"version":1,"settings":{"rules":{"pressure":{"level":"info"}}}}"#.utf8)
        // The detail text is Foundation's; only the type and the file name are ours.
        let error = #expect(throws: SettingsError.self) { try DaemonSettings.decodeValidated(data) }
        guard case .invalid(let message)? = error else { Issue.record("expected .invalid"); return }
        #expect(message.hasPrefix("settings.json: "))
    }

    @Test func unknownVersionThrows() {
        #expect(throws: SettingsError.unsupportedVersion(2)) {
            try DaemonSettings.decodeValidated(Data(#"{"version":2,"settings":{}}"#.utf8))
        }
    }

    @Test func corruptFileThrows() {
        #expect(throws: (any Error).self) { try DaemonSettings.decodeValidated(Data("{".utf8)) }
    }

    @Test func validation() throws {
        #expect(DaemonSettings().validationProblem() == nil)
        // The ranges of earlier builds, which an 8-core 8 GB Mac keeps.
        let small = Machine(cores: 8, memoryBytes: 8 << 30, bootVolumeBytes: 256_000_000_000)
        let cases: [(String, (inout DaemonSettings) -> Void)] = [
            ("Size cap must be 1 to 50 GB", { $0.sizeCapBytes = 999_999_999 }),
            ("Size cap must be 1 to 50 GB", { $0.sizeCapBytes = 50_000_000_001 }),
            ("A terminal bundle ID is empty", { $0.terminalBundleIDs = ["com.apple.Terminal", " \n"] }),
            ("Use at most 32 terminal apps", { $0.terminalBundleIDs = (0...32).map { "app.\($0)" } }),
            ("Sustained CPU must be 10 to 1000%", { $0.rules.sustainedCPU.percent = 9 }),
            ("Sustained CPU must be 10 to 1000%", { $0.rules.sustainedCPU.percent = 1001 }),
            ("Sustained CPU time must be 1 to 60 min", { $0.rules.sustainedCPU.minutes = 0 }),
            ("Sustained CPU time must be 1 to 60 min", { $0.rules.sustainedCPU.minutes = 61 }),
            ("Memory growth time must be 10 to 120 min", { $0.rules.memoryGrowth.minutes = 9 }),
            ("Memory growth time must be 10 to 120 min", { $0.rules.memoryGrowth.minutes = 121 }),
            ("Memory growth must be 50 to 16384 MB", { $0.rules.memoryGrowth.megabytes = 49 }),
            ("Memory growth must be 50 to 16384 MB", { $0.rules.memoryGrowth.megabytes = 16385 }),
            ("Memory jump must be 128 to 16384 MB", { $0.rules.memoryJump.megabytes = 127 }),
            ("Memory jump must be 128 to 16384 MB", { $0.rules.memoryJump.megabytes = 16385 }),
            ("Thermal time must be 1 to 60 min", { $0.rules.thermal.minutes = 0 }),
            ("Thermal time must be 1 to 60 min", { $0.rules.thermal.minutes = 61 }),
            ("Disk writes must be 1 to 1000 GB per hour", { $0.rules.diskWrites.bytesPerHour = 999_999_999 }),
            ("Network must be 1 to 10000 MB/s", { $0.rules.network.bytesPerSecond = 10_000_000_001 }),
            ("Network time must be 1 to 60 min", { $0.rules.network.minutes = 0 }),
            ("Energy impact must be 10 to 5000", { $0.rules.energy.impact = 9 }),
            ("Energy time must be 1 to 60 min", { $0.rules.energy.minutes = 61 }),
            ("GPU must be 10 to 100%", { $0.rules.gpu.percent = 101 }),
            ("GPU time must be 1 to 60 min", { $0.rules.gpu.minutes = 0 }),
            ("System CPU must be 10 to 100%", { $0.rules.systemCPU.critical = 101 }),
            ("System CPU warning must be below critical", { $0.rules.systemCPU.warning = 90 }),
            ("System CPU time must be 1 to 60 min", { $0.rules.systemCPU.minutes = 0 }),
            ("Swap must be 10 to 200% of memory", { $0.rules.swap.percentOfMemory = 9 }),
            ("Free space must be 1 to 50%", { $0.rules.freeSpace.percentFree = 51 }),
        ]
        for (message, change) in cases {
            var settings = DaemonSettings()
            change(&settings)
            #expect(settings.validationProblem(for: small) == message)
        }
        // The ranges grow with the Mac.
        let large = Machine(cores: 24, memoryBytes: 192 << 30, bootVolumeBytes: 8_000_000_000_000)
        var big = DaemonSettings()
        big.rules.sustainedCPU.percent = 2400
        big.rules.memoryJump.megabytes = 196_608
        #expect(big.validationProblem(for: large) == nil)
        big.rules.sustainedCPU.percent = 2401
        #expect(big.validationProblem(for: large) == "Sustained CPU must be 10 to 2400%")
        // An app's own values are checked as the global ones.
        var app = DaemonSettings()
        var own = AlertRules.AppOverride()
        own.gpu = AlertRules.GPU()
        own.gpu?.percent = 101
        app.rules.apps["/Applications/A.app"] = own
        #expect(app.validationProblem(for: small) == "A.app: GPU must be 10 to 100%")
        app.rules.apps = Dictionary(uniqueKeysWithValues: (0...AlertRules.maxApps).map { ("app\($0)", AlertRules.AppOverride()) })
        #expect(app.validationProblem(for: small) == "Use at most 50 apps with their own alert rules")
        var low = DaemonSettings()
        low.sizeCapBytes = 100_000_000
        let data = try low.encoded()
        #expect(throws: SettingsError.invalid("Size cap must be 1 to 50 GB")) { try DaemonSettings.decodeValidated(data) }
    }

    @Test func sizeCapChoicesAreValid() {
        for cap in DaemonSettings.sizeCapChoices {
            var settings = DaemonSettings()
            settings.sizeCapBytes = cap
            #expect(settings.validationProblem() == nil)
        }
    }

    @Test func addTerminalReadsBundleID() throws {
        var settings = DaemonSettings()
        let calculator = URL(filePath: "/System/Applications/Calculator.app")
        try settings.addTerminal(appAt: calculator)
        #expect(settings.terminalBundleIDs.last == "com.apple.calculator")
        let count = settings.terminalBundleIDs.count
        try settings.addTerminal(appAt: calculator)
        #expect(settings.terminalBundleIDs.count == count)
        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("amx-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bare) }
        #expect(throws: SettingsError.invalid("\(bare.lastPathComponent) has no bundle ID")) { try settings.addTerminal(appAt: bare) }
    }

    @Test func systemCPULevelBoundaries() {
        var rule = AlertRules.SystemCPU()
        #expect([rule.warning - 1, rule.warning, rule.critical].map { rule.level(Double($0)) } == [0, 1, 2])
        rule.enabled = false
        #expect(rule.level(100) == 0)
    }
}
