// MIT License. See Packaging/Credits.html.
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
            // A raw `system_profiler` type key is a row only for memory, where it holds the size.
            if key.range(of: "^SP.*DataType$", options: .regularExpression) != nil, key != "SPMemoryDataType" { continue }
            switch item[key]! {
            case let list as [[String: Any]]:
                children += list.flatMap { nodes($0, fallback: label(key), parent: id) }
            case let dict as [String: Any]:
                children += nodes(dict, fallback: label(key), parent: id)
            case let value:
                let name = label(key)
                var shown = text(value)
                // A value that starts with its own key ("Vendor Apple" under "Vendor") loses the repeat.
                if shown.count > name.count + 1, shown.lowercased().hasPrefix(name.lowercased() + " ") {
                    shown = String(shown.dropFirst(name.count + 1))
                }
                if key == "number_processors" { shown = processors(shown, clusters: ChipInfo.current().clusters) }
                properties.append(.init(key: key, label: name, value: shown))
            }
        }
        return HardwareNode(id: id, name: name, properties: properties, children: children.isEmpty ? nil : children)
    }

    /// "proc 15:5:10:0" (total, then cores per cluster from the fastest) becomes "15 cores (5 Super, 10 Performance)".
    /// A value that does not parse, or does not match the clusters, stays as it is.
    static func processors(_ raw: String, clusters: [ChipInfo.Cluster]) -> String {
        let counts = raw.dropFirst(5).split(separator: ":").compactMap { Int($0) }
        guard raw.hasPrefix("proc "), counts.count > clusters.count, counts.dropFirst().prefix(clusters.count).reduce(0, +) == counts[0]
        else { return raw }
        let parts = zip(clusters, counts.dropFirst()).map { "\($1) \($0.name)" }
        return "\(counts[0]) cores (\(parts.joined(separator: ", ")))"
    }

    /// A key as a row title: `_spdisplays_resolution` becomes "Resolution".
    public static func label(_ key: String) -> String {
        var s = Substring(key)
        if s.hasPrefix("_") { s.removeFirst() }
        let key = stripped(String(s)).0
        return names[key] ?? capitalized(spaced(key))
    }

    /// Plain names for keys the general rule cannot spell (acronyms, joined words). Other keys keep the general rule.
    private static let names = [
        "pixelresolution": "Pixel resolution", "mtlgpufamilysupport": "Metal support", "ndrvs": "Connected displays",
        "display-product-id": "Display product ID", "display-vendor-id": "Display vendor ID",
        "display-week": "Manufacture week", "display-year": "Manufacture year", "displayID": "Display ID",
        "ac_charger_ID": "Charger ID", "ac_charger_family": "Charger family", "ac_charger_watts": "Charger watts",
        "battery_pcb_lot_code": "Battery PCB lot code", "dimm_type": "DIMM type", "dimm_manufacturer": "DIMM manufacturer",
        "boot_rom_version": "Boot ROM version", "os_loader_version": "OS loader version", "bsd_name": "BSD name",
        "iocontent": "I/O content", "is_internal_disk": "Internal disk", "smart_status": "S.M.A.R.T. status",
        "ip_address": "IP address", "number_processors": "Processors", "platform_UUID": "Platform UUID",
        "USBDeviceKeyLinkSpeed": "Link speed", "USBDeviceKeyPowerAllocation": "Power allocation",
        "USBDeviceKeyProductID": "Product ID", "USBDeviceKeyProductVersion": "Product version",
        "USBKeyHardwareType": "Hardware type", "USBKeyLocationID": "Location ID",
        "coreaudio_device_srate": "Sample rate", "coreaudio_device_transport": "Transport",
        "coreaudio_device_manufacturer": "Manufacturer", "coreaudio_device_input": "Input channels",
        "coreaudio_device_output": "Output channels", "coreaudio_default_audio_input_device": "Default input",
        "coreaudio_default_audio_output_device": "Default output", "coreaudio_default_audio_system_device": "Default system output",
        "coreaudio_input_source": "Input source", "coreaudio_output_source": "Output source",
        "SPMemoryDataType": "Size", "trim_support": "TRIM support", "model-id": "Model ID",
    ]

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
