// Derived from mac-performance-monitor. Copyright (c) 2026 Mac Performance Monitor contributors, MIT License;
// the full notice is in Packaging/Credits.html.
import Foundation

/// A bundled "what is this process?" glossary, matched locally: no process name leaves the Mac.
public struct Glossary: Decodable, Sendable {
    public struct Match: Decodable, Sendable, Equatable {
        let name, bundleID, bundleIDPrefix, path, pathPrefix, pathSuffix, pathPattern, namePattern: String?
    }

    public struct Entry: Decodable, Sendable, Equatable {
        let match: Match
        public let title: String
        public let description: String
        public let category: String
        public let vendor: String?
        public let url: String?
        /// High CPU or memory is normal for this process (WindowServer).
        public let expectedHigh: Bool?
    }

    public let version: Int
    public let entries: [Entry]

    /// The best entry, most specific first: exact bundle ID, exact path, longest path suffix, longest path
    /// substring, exact name, longest bundle-ID prefix, longest path prefix, name substring. Path-aware rules
    /// keep a generic name such as `log` from labelling unrelated software.
    public func lookup(name: String, bundleID: String?, path: String?) -> Entry? {
        // The kernel truncates a process name to 15 characters; entries use the file name of the executable.
        let full = path.map { ($0 as NSString).lastPathComponent }
        if let bundleID, let e = entries.first(where: { $0.match.bundleID == bundleID }) { return e }
        if let path, let e = entries.first(where: { $0.match.path == path }) { return e }
        if let path, let e = longest(\.match.pathSuffix, where: path.hasSuffix) { return e }
        if let path, let e = longest(\.match.pathPattern, where: path.contains) { return e }
        if let e = entries.first(where: { $0.match.name.map { $0 == name || $0 == full } ?? false }) { return e }
        if let bundleID, let e = longest(\.match.bundleIDPrefix, where: bundleID.hasPrefix) { return e }
        if let path, let e = longest(\.match.pathPrefix, where: path.hasPrefix) { return e }
        return entries.first {
            $0.match.namePattern.map { name.localizedCaseInsensitiveContains($0) || full?.localizedCaseInsensitiveContains($0) == true } ?? false
        }
    }

    private func longest(_ key: KeyPath<Entry, String?>, where matches: (String) -> Bool) -> Entry? {
        entries.filter { $0[keyPath: key].map(matches) ?? false }.max { ($0[keyPath: key]?.count ?? 0) < ($1[keyPath: key]?.count ?? 0) }
    }
}
