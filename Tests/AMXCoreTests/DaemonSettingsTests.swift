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
    }

    @Test func fileShape() throws {
        let top = try json(DaemonSettings())
        #expect(Set(top.keys) == ["settings", "version"])
        #expect(top["version"] as? Int == 1)
        let body = try #require(top["settings"] as? [String: Any])
        #expect(Set(body.keys) == ["rules", "size_cap_bytes", "terminal_bundle_ids"])
        let rules = try #require(body["rules"] as? [String: Any])
        #expect(Set(rules.keys) == ["memory_growth", "memory_jump", "pressure", "sustained_cpu", "thermal"])
        let pressure = try #require(rules["pressure"] as? [String: Any])
        #expect(pressure["level"] as? String == "warning")
    }

    @Test func missingKeysTakeDefaults() throws {
        let data = Data(#"{"version":1,"settings":{"size_cap_bytes":5000000000,"rules":{"pressure":{"level":"critical"}}}}"#.utf8)
        var expected = DaemonSettings()
        expected.sizeCapBytes = 5_000_000_000
        expected.rules.pressure.level = .critical
        #expect(try DaemonSettings.decodeValidated(data) == expected)
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
        let cases: [(String, (inout DaemonSettings) -> Void)] = [
            ("Size cap must be 1 to 50 GB", { $0.sizeCapBytes = 999_999_999 }),
            ("Size cap must be 1 to 50 GB", { $0.sizeCapBytes = 50_000_000_001 }),
            ("A terminal bundle ID is empty", { $0.terminalBundleIDs = ["com.apple.Terminal", " \n"] }),
            ("Use at most 32 terminal apps", { $0.terminalBundleIDs = (0...32).map { "app.\($0)" } }),
            ("Sustained CPU must be 10 to 1000 %", { $0.rules.sustainedCPU.percent = 9 }),
            ("Sustained CPU must be 10 to 1000 %", { $0.rules.sustainedCPU.percent = 1001 }),
            ("Sustained CPU time must be 1 to 60 min", { $0.rules.sustainedCPU.minutes = 0 }),
            ("Sustained CPU time must be 1 to 60 min", { $0.rules.sustainedCPU.minutes = 61 }),
            ("Memory growth time must be 10 to 120 min", { $0.rules.memoryGrowth.minutes = 9 }),
            ("Memory growth time must be 10 to 120 min", { $0.rules.memoryGrowth.minutes = 121 }),
            ("Memory growth must be 50 to 16384 MB", { $0.rules.memoryGrowth.megabytes = 49 }),
            ("Memory growth must be 50 to 16384 MB", { $0.rules.memoryGrowth.megabytes = 16385 }),
            ("Memory jump must be 256 to 16384 MB", { $0.rules.memoryJump.megabytes = 255 }),
            ("Memory jump must be 256 to 16384 MB", { $0.rules.memoryJump.megabytes = 16385 }),
            ("Thermal time must be 1 to 60 min", { $0.rules.thermal.minutes = 0 }),
            ("Thermal time must be 1 to 60 min", { $0.rules.thermal.minutes = 61 }),
        ]
        for (message, change) in cases {
            var settings = DaemonSettings()
            change(&settings)
            #expect(settings.validationProblem() == message)
        }
        var low = DaemonSettings()
        low.sizeCapBytes = 100_000_000
        let data = try low.encoded()
        #expect(throws: SettingsError.invalid("Size cap must be 1 to 50 GB")) { try DaemonSettings.decodeValidated(data) }
    }
}
