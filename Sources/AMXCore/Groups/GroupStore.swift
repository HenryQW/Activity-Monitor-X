import Foundation

/// Readable in the app (`localizedDescription`) and in `amx` (`description`).
public enum GroupStoreError: LocalizedError, CustomStringConvertible, Equatable {
    case unsupportedVersion(Int)
    case duplicateID(UUID)

    public var description: String {
        switch self {
        case .unsupportedVersion(let found): "groups.json has version \(found); this app reads version 1"
        case .duplicateID(let id): "groups.json has two groups with id \(id)"
        }
    }

    public var errorDescription: String? { description }
}

/// `groups.json`: `{"version":1,"groups":[…]}`. Only the app writes it; `amx` reads it.
public enum GroupStore {
    private static let version = 1

    private struct Version: Decodable { let version: Int }
    private struct File: Codable {
        let version: Int
        let groups: [ProcessGroup]
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ActivityMonitorX/groups.json")
    }

    public static func load(from url: URL) throws -> [ProcessGroup] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let found = try JSONDecoder().decode(Version.self, from: data).version
        guard found == version else { throw GroupStoreError.unsupportedVersion(found) }
        let groups = try JSONDecoder().decode(File.self, from: data).groups
        var seen = Set<UUID>()
        for group in groups where !seen.insert(group.id).inserted { throw GroupStoreError.duplicateID(group.id) }
        return groups
    }

    public static func save(_ groups: [ProcessGroup], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(version: version, groups: groups)).write(to: url, options: .atomic)
    }
}
