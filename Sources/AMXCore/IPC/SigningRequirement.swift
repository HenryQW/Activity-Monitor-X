import CryptoKit
import Foundation
import Security

public enum SigningRequirement {
    public static func string(leafSHA1Hex: String) -> String {
        #"(identifier "\#(AMX.bundleID)" or identifier "\#(AMX.cliID)" or identifier "\#(AMX.devBundleID)") and certificate leaf = H"\#(leafSHA1Hex)""#
    }

    /// SHA-1 of this process's leaf signing certificate, lowercase hex; nil if unsigned or ad-hoc (no certificates).
    public static func ownLeafSHA1() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let leaf = (dict[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}
