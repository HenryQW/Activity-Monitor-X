// MIT License. See Packaging/Credits.html.
import Foundation
import Security

public enum CodeSigning {
    private static let cache = PathCache<String?>()

    /// Resolves on every cache miss; the 30-per-tick budget is enforced by the caller.
    public static func teamID(forPath path: String) -> String? {
        cache.value(for: path) {
            var staticCode: SecStaticCode?
            guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
                  let staticCode else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let dict = info as? [String: Any] else { return nil }
            return dict[kSecCodeInfoTeamIdentifier as String] as? String
        }
    }
}
