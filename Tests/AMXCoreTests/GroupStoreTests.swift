import Foundation
import Testing
@testable import AMXCore

@Suite struct GroupStoreTests {
    /// In a directory that does not exist yet.
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("amx-\(UUID().uuidString)")
            .appendingPathComponent("groups.json")
    }

    private func write(_ text: String) throws -> URL {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func ruleJSONShape() throws {
        let rule = GroupRule.all([
            .condition(.init(field: .name, op: .contains, value: "code")),
            .not(.condition(.init(field: .teamID, op: .equals, value: "ABC"))),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(rule), as: UTF8.self)
        #expect(json == #"{"all":[{"field":"name","op":"contains","value":"code"},{"not":{"field":"team_id","op":"is","value":"ABC"}}]}"#)
        #expect(try JSONDecoder().decode(GroupRule.self, from: Data(json.utf8)) == rule)
    }

    @Test func roundTrip() throws {
        let groups = [
            ProcessGroup(name: "Dev", symbol: "hammer", color: .green,
                         rule: .any([.condition(.init(field: .bundleID, op: .startsWith, value: "com.apple."))])),
            ProcessGroup(name: "Empty"),
        ]
        let url = tempURL()
        try GroupStore.save(groups, to: url)
        #expect(try GroupStore.load(from: url) == groups)
    }

    /// Red and yellow were group colours before COL-1 kept them for levels: a saved group reads as blue.
    @Test func retiredColorReadsAsBlue() throws {
        let colors = try JSONDecoder().decode([GroupColor].self, from: Data(#"["red","yellow","green"]"#.utf8))
        #expect(colors == [.blue, .blue, .green])
    }

    @Test func missingFileIsEmpty() throws {
        #expect(try GroupStore.load(from: tempURL()).isEmpty)
    }

    @Test func corruptFileThrows() throws {
        let url = try write("{")
        #expect(throws: DecodingError.self) { try GroupStore.load(from: url) }
    }

    @Test func unknownVersionThrows() throws {
        let url = try write(#"{"version":2,"groups":[]}"#)
        #expect(throws: GroupStoreError.unsupportedVersion(2)) { try GroupStore.load(from: url) }
    }

    @Test func duplicateIDThrows() throws {
        let group = ProcessGroup(name: "A")
        let url = tempURL()
        try GroupStore.save([group, group], to: url)
        #expect(throws: GroupStoreError.duplicateID(group.id)) { try GroupStore.load(from: url) }
    }

    @Test func unknownRuleKeyThrows() {
        for json in [#"{"xor":[]}"#, #"{"all":[],"any":[]}"#] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(GroupRule.self, from: Data(json.utf8)) }
        }
    }
}
