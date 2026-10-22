// Derived from mac-performance-monitor (Zesty0wl), MIT License. See Packaging/Credits.html.
import Foundation

public enum HardwareError: Error, Equatable {
    case timedOut
    case failed(Int32, String)
}

public struct HardwareNode: Sendable, Identifiable, Equatable {
    public struct Property: Sendable, Equatable {
        public let key, label, value: String
    }

    /// Names from the section down, joined with "/".
    public let id: String
    public let name: String
    public let properties: [Property]
    public let children: [HardwareNode]?

    public func value(_ key: String) -> String? {
        properties.first { $0.key == key }?.value
    }
}

public enum HardwareInventory {
    public static let sections: [(type: String, title: String)] = [
        ("SPHardwareDataType", "Hardware"),
        ("SPMemoryDataType", "Memory"),
        ("SPDisplaysDataType", "Graphics and Displays"),
        ("SPNVMeDataType", "NVMe"),
        ("SPStorageDataType", "Storage"),
        ("SPPowerDataType", "Power"),
        ("SPUSBHostDataType", "USB"),
        ("SPThunderboltDataType", "Thunderbolt/USB4"),
        ("SPBluetoothDataType", "Bluetooth"),
        ("SPNetworkDataType", "Network"),
        ("SPAudioDataType", "Audio"),
        ("SPCameraDataType", "Camera"),
    ]

    private static let dropped = ["serial", "uid", "udid", "unique", "address"]

    public static func parse(_ json: Data) throws -> [HardwareNode] {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return sections.compactMap { type, title in
            let items = (root[type] as? [[String: Any]] ?? []).flatMap { nodes($0, fallback: title, parent: title) }
            return items.isEmpty ? nil : HardwareNode(id: title, name: title, properties: [], children: items)
        }
    }

    /// An item with a `_name` is one node; one whose values are all dictionaries is a set of nodes named by key.
    private static func nodes(_ item: [String: Any], fallback: String, parent: String) -> [HardwareNode] {
        if item["_name"] == nil, !item.isEmpty, item.values.allSatisfy({ $0 is [String: Any] }) {
            return item.keys.sorted().map { node(named: $0, item[$0] as! [String: Any], parent: parent) }
        }
        return [node(named: item["_name"] as? String ?? fallback, item, parent: parent)]
    }

    private static func node(named name: String, _ item: [String: Any], parent: String) -> HardwareNode {
        let id = parent + "/" + name
        var properties: [HardwareNode.Property] = []
        var children: [HardwareNode] = []
        for key in item.keys.sorted() where key != "_name" {
            let lower = key.lowercased()
            if dropped.contains(where: lower.contains) { continue }
            switch item[key]! {
            case let list as [[String: Any]]:
                children += list.flatMap { nodes($0, fallback: label(key), parent: id) }
            case let dict as [String: Any]:
                children += nodes(dict, fallback: label(key), parent: id)
            case let value:
                properties.append(.init(key: key, label: label(key), value: text(value)))
            }
        }
        return HardwareNode(id: id, name: name, properties: properties, children: children.isEmpty ? nil : children)
    }

    /// A key as a row title: `_spdisplays_resolution` becomes "Resolution".
    public static func label(_ key: String) -> String {
        var s = Substring(key)
        if s.hasPrefix("_") { s.removeFirst() }
        return capitalized(spaced(stripped(String(s)).0))
    }

    /// A value for display: `spdisplays_supported` becomes "Supported", `true` becomes "Yes".
    static func text(_ value: Any) -> String {
        switch value {
        case let s as String:
            let (rest, hadPrefix) = stripped(s)
            return hadPrefix ? capitalized(spaced(rest)) : spaced(rest)
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "Yes" : "No") : n.stringValue
        case let list as [Any]:
            return list.map(text).joined(separator: ", ")
        default:
            return "\(value)"
        }
    }

    private static func stripped(_ s: String) -> (String, Bool) {
        guard let r = s.range(of: "^sp[A-Za-z]+_", options: .regularExpression) else { return (s, false) }
        return (String(s[r.upperBound...]), true)
    }

    private static func spaced(_ s: String) -> String { s.replacingOccurrences(of: "_", with: " ") }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// One `system_profiler` run for every section. Output is read on background tasks while the process runs.
    public static func capture(timeout: Duration = .seconds(30)) async throws -> [HardwareNode] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "-detailLevel", "mini"] + sections.map(\.type)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let (exits, exit) = AsyncStream<Int32>.makeStream()
        p.terminationHandler = { exit.yield($0.terminationStatus) }
        try p.run()
        let outHandle = out.fileHandleForReading, errHandle = err.fileHandleForReading
        let stdout = Task.detached { (try? outHandle.readToEnd()) ?? Data() }
        let stderr = Task.detached { (try? errHandle.readToEnd()) ?? Data() }
        let status = await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await exits.first { _ in true } }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
        guard let status else {
            p.terminate()
            try Task.checkCancellation()
            throw HardwareError.timedOut
        }
        guard status == 0 else {
            let message = String(decoding: await stderr.value, as: UTF8.self)
            throw HardwareError.failed(status, message.split(separator: "\n").first.map(String.init) ?? "")
        }
        return try parse(await stdout.value)
    }
}
