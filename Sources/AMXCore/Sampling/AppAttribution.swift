import Foundation

public struct AppInfo: Sendable, Equatable {
    public let appPath: String?
    public let appName: String
    public let bundleID: String?
}

/// Maps an executable to its outermost `.app` bundle, so helpers group under the parent app.
public enum AppAttribution {
    private static let cache = PathCache<AppInfo>()

    /// Apps whose children keep their own path-based app (shells and CLI tools started in a terminal).
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.kk2.rootshell",
    ]

    /// The responsible process's app when it lies in an `.app` that is not a terminal, else the path rule.
    public static func app(forExecutable path: String?, processName: String, responsiblePath: String?) -> AppInfo {
        if responsiblePath?.contains(".app/") == true {
            let responsible = app(forExecutable: responsiblePath, processName: processName)
            if !terminalBundleIDs.contains(responsible.bundleID ?? "") { return responsible }
        }
        return app(forExecutable: path, processName: processName)
    }

    public static func app(forExecutable path: String?, processName: String) -> AppInfo {
        guard let path, let range = path.range(of: ".app/") else {
            return AppInfo(appPath: nil, appName: processName, bundleID: nil)
        }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        return cache.value(for: appPath) {
            AppInfo(appPath: appPath,
                    appName: String(path[..<range.lowerBound].split(separator: "/").last ?? ""),
                    bundleID: bundleID(inApp: appPath))
        }
    }

    private static func bundleID(inApp appPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: appPath + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }
}

/// Dictionary cache keyed by path; cleared when full (cap 2048).
final class PathCache<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Value] = [:]

    func value(for key: String, compute: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let hit = storage[key] { return hit }
        let v = compute()
        if storage.count >= 2048 { storage.removeAll() }
        storage[key] = v
        return v
    }
}
