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
    /// A system symbol that says what the node is: on things only (sections, buses, devices, displays, volumes), never on
    /// a set of values or a group; set at parse time.
    public var symbol: String?

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

    /// Each section's symbol; a node takes its section's unless it is a kind with its own (`symbol(of:)`).
    static let sectionSymbols = [
        "Hardware": "cpu", "Memory": "memorychip", "Graphics and Displays": "display", "NVMe": "internaldrive",
        "Storage": "internaldrive", "Power": "battery.100", "USB": "cable.connector", "Thunderbolt/USB4": "bolt.horizontal",
        "Bluetooth": "dot.radiowaves.left.and.right", "Network": "network", "Audio": "speaker.wave.2", "Camera": "camera",
    ]
    /// Ports are listed whether or not anything is plugged in: a bus with no devices under it is not shown.
    private static let portSections: Set = ["SPUSBHostDataType", "SPThunderboltDataType"]
    /// Devices that are paired but not connected go in one group, closed, after the connected ones.
    private static let notConnected = "device_not_connected"

    public static func parse(_ json: Data) throws -> [HardwareNode] {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return sections.compactMap { type, title in
            let list = (root[type] as? [[String: Any]] ?? []).filter { !portSections.contains(type) || $0["_items"] != nil }
            let symbol = sectionSymbols[title]
            let items = list.flatMap { nodes($0, fallback: title, parent: title, symbol: symbol) }
            var section = HardwareNode(id: title, name: title, properties: [], children: items)
            section.symbol = symbol
            return items.isEmpty ? nil : section
        }
    }

    /// An item with a `_name` is one node; one whose values are all dictionaries is a set of nodes named by key. Both are
    /// things, except a raw `_name` (`sppower_battery_information`, lower case with underscores): that, and an item with
    /// no name ("Controller properties"), is a set of values.
    private static func nodes(_ item: [String: Any], fallback: String, parent: String, symbol: String?) -> [HardwareNode] {
        if item["_name"] == nil, !item.isEmpty, item.values.allSatisfy({ $0 is [String: Any] }) {
            return item.keys.sorted().map { node(named: $0, item[$0] as! [String: Any], parent: parent, symbol: symbol, thing: true) }
        }
        return [node(named: item["_name"] as? String ?? fallback, item, parent: parent, symbol: symbol, thing: (item["_name"] as? String).map { !($0.contains("_") && $0 == $0.lowercased()) } ?? false)]
    }

    /// A Bluetooth device by its type, a display, a volume inside or outside the Mac; else the parent's symbol.
    static func symbol(of item: [String: Any], inherited: String?) -> String? {
        switch item["device_minorType"] as? String {
        case "Mouse": return "computermouse"
        case "Keyboard": return "keyboard"
        case "Headphones": return "headphones"
        default: break
        }
        if item["_spdisplays_resolution"] != nil {
            return item["spdisplays_connection_type"] as? String == "spdisplays_internal" ? "laptopcomputer" : "display"
        }
        if item["mount_point"] != nil {
            return (item["physical_drive"] as? [String: Any])?["is_internal_disk"] as? String == "yes" ? "internaldrive" : "externaldrive"
        }
        return inherited
    }

    /// `symbol` passes down to the things inside; the node shows it only when it is a `thing`.
    private static func node(named rawName: String, _ item: [String: Any], parent: String, symbol inherited: String?, thing: Bool) -> HardwareNode {
        let symbol = symbol(of: item, inherited: inherited)
        // A built-in display is named by its type, as System Settings names it ("Color LCD" is the panel's own name).
        let name = (item["spdisplays_display_type"] as? String).map(displayType) ?? rawName
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
                if key == notConnected {
                    let group = id + "/Not Connected"
                    var node = HardwareNode(id: group, name: "Not Connected", properties: [],
                                            children: list.flatMap { nodes($0, fallback: label(key), parent: group, symbol: symbol) })
                    if !list.isEmpty { children.append(node) }
                } else {
                    children += list.flatMap { nodes($0, fallback: label(key), parent: id, symbol: symbol) }
                }
            case let dict as [String: Any]:
                children += nodes(dict, fallback: label(key), parent: id, symbol: symbol)
            case let value:
                let name = label(key)
                var shown = key == "spdisplays_display_type" ? displayType(value as? String ?? "") : text(value)
                // A value that starts with its own key ("Vendor Apple" under "Vendor") loses the repeat.
                if shown.count > name.count + 1, shown.lowercased().hasPrefix(name.lowercased() + " ") {
                    shown = String(shown.dropFirst(name.count + 1))
                }
                if key == "number_processors" { shown = processors(shown, clusters: ChipInfo.current().clusters) }
                // system_profiler gives some display facts twice ("_spdisplays_resolution" and "spdisplays_resolution",
                // pixels and pixel resolution): a value that an earlier row with a label word in common shows is left out.
                if properties.contains(where: { $0.value == shown && sharesWord($0.label, name) }) { continue }
                properties.append(.init(key: key, label: name, value: shown))
            }
        }
        var node = HardwareNode(id: id, name: name, properties: properties, children: children.isEmpty ? nil : children)
        node.symbol = thing ? symbol : nil
        return node
    }

    /// "Pixels" and "Pixel resolution" share a word; "Main" and "Online" do not.
    private static func sharesWord(_ a: String, _ b: String) -> Bool {
        let words = { (s: String) in s.lowercased().split(separator: " ") }
        return words(a).contains { x in words(b).contains { $0.hasPrefix(x) || x.hasPrefix($0) } }
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

    /// A display's "1512 x 982 @ 120.00Hz" becomes "1512 x 982, 120 Hz"; a value without a rate stays as it is.
    public static func resolution(_ raw: String) -> String {
        let parts = raw.components(separatedBy: " @ ")
        guard parts.count == 2, parts[1].hasSuffix("Hz"), let rate = Double(parts[1].dropLast(2)) else { return raw }
        return "\(parts[0]), \(rate.formatted(.number.precision(.fractionLength(0...2)))) Hz"
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

    /// The system's own text for a display type ("Built-in Liquid Retina XDR Display"); the general rule for one it lacks.
    static func displayType(_ raw: String) -> String {
        let shown = Bundle(path: "/System/Library/SystemProfiler/SPDisplaysReporter.spreporter")?
            .localizedString(forKey: raw, value: nil, table: nil)
        return shown.flatMap { $0 == raw ? nil : $0 } ?? text(raw)
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
