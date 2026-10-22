// MIT License. See Packaging/Credits.html.
import Foundation
import Security

public enum CodeSigning {
    /// Resolves on every call; the caller caches results and enforces the 30-per-tick budget.
    public static func teamID(forPath path: String) -> String? {
        guard !onSealedVolume(path) else { return nil }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Platform binaries on the sealed system volume have no Team ID, so they need no lookup.
    /// `/usr/local` and the data volume are writable and can hold third-party code.
    static func onSealedVolume(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") || path.hasPrefix("/System/Volumes/Data/") { return false }
        return ["/System/", "/bin/", "/sbin/", "/usr/"].contains { path.hasPrefix($0) }
    }
}
