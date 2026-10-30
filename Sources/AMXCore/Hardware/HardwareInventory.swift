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
    /// A Bluetooth device's address, for its Connect, Disconnect and Forget actions; never a row (`dropped`).
    public var address: String?

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

    public static func parse(_ json: Data) throws -> [HardwareNode] { parse(root: try object(json)) }

    private static func object(_ json: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        return root
    }

    private static func parse(root: [String: Any]) -> [HardwareNode] {
        let root = byThing(root)
        return sections.compactMap { type, title in
            let list = (root[type] as? [[String: Any]] ?? []).filter { !portSections.contains(type) || $0["_items"] != nil }
            let symbol = sectionSymbols[title]
            let items = list.flatMap { nodes($0, fallback: title, parent: title, symbol: symbol) }
            var section = HardwareNode(id: title, name: title, properties: [], children: items)
            section.symbol = symbol
            return items.isEmpty ? nil : section
        }
    }

    /// Each thing at the top of its section, its parts inside it (SCR-25): a display beside its GPU, not under it; Storage
    /// by drive, each drive with its facts (its NVMe entry, which then leaves NVMe) and its volumes inside, which no longer
    /// repeat the drive.
    static func byThing(_ root: [String: Any]) -> [String: Any] {
        var root = root
        let display = "spdisplays_ndrvs"
        if let gpus = root["SPDisplaysDataType"] as? [[String: Any]] {
            root["SPDisplaysDataType"] = gpus.flatMap { gpu in
                [gpu.filter { $0.key != display }] + (gpu[display] as? [[String: Any]] ?? [])
            }
        }
        guard let volumes = root["SPStorageDataType"] as? [[String: Any]] else { return root }
        var controllers = root["SPNVMeDataType"] as? [[String: Any]] ?? []
        var drives: [[String: Any]] = []
        for volume in volumes {
            let physical = volume["physical_drive"] as? [String: Any] ?? [:]
            let name = physical["device_name"] as? String ?? "Drive"
            let bare = volume.filter { $0.key != "physical_drive" }
            if let i = drives.firstIndex(where: { $0["_name"] as? String == name }) {
                drives[i]["volumes"] = (drives[i]["volumes"] as? [[String: Any]] ?? []) + [bare]
                continue
            }
            var drive = physical.filter { $0.key != "device_name" }
            for c in controllers.indices {
                guard var items = controllers[c]["_items"] as? [[String: Any]],
                      let i = items.firstIndex(where: { $0["_name"] as? String == name }) else { continue }
                drive.merge(items.remove(at: i)) { old, _ in old }
                controllers[c]["_items"] = items
            }
            drive["_name"] = name
            drive["volumes"] = [bare]
            drives.append(drive)
        }
        root["SPStorageDataType"] = drives
        root["SPNVMeDataType"] = controllers.filter { ($0["_items"] as? [Any])?.isEmpty == false }
        return root
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

    /// A Bluetooth device by its type, a display, a drive inside or outside the Mac; else the parent's symbol (a volume takes
    /// its drive's).
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
        // A drive by its own flag; a volume inside a drive takes the drive's.
        if let isInternal = item["is_internal_disk"] as? String { return isInternal == "yes" ? "internaldrive" : "externaldrive" }
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
                var name = label(key)
                var shown = key == "spdisplays_display_type" ? displayType(value as? String ?? "") : text(value)
                // Bytes as a size; left out where the item also gives the size in words ("size" beside "size_in_bytes").
                if key.hasSuffix("_in_bytes") {
                    let base = String(key.dropLast(9))
                    if item[base] != nil { continue }
                    name = label(base)
                    if let n = value as? NSNumber { shown = n.int64Value.formatted(.byteCount(style: .file)) }
                }
                if key.hasSuffix("spdisplays_resolution") { shown = resolution(shown) }
                // "3024x1964Retina" as System Information shows it: "3024 x 1964 Retina".
                if key == "spdisplays_pixelresolution" {
                    shown = shown.replacingOccurrences(of: "(\\d)x(\\d+)([A-Za-z]*)", with: "$1 x $2 $3", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
                // A value that starts with its own key ("Vendor Apple" under "Vendor") loses the repeat.
                if shown.count > name.count + 1, shown.lowercased().hasPrefix(name.lowercased() + " ") {
                    shown = String(shown.dropFirst(name.count + 1))
                }
                if key == "number_processors" { shown = processors(shown, clusters: ChipInfo.current().clusters) }
                // system_profiler gives some display facts twice ("_spdisplays_resolution" and "spdisplays_resolution",
                // pixels and pixel resolution): a value that an earlier row with a label word in common shows is left out.
                // System Information calls the pixel resolution "Resolution", which shares no word with "Pixels".
                if properties.contains(where: { $0.value == shown && (sharesWord($0.label, name) || $0.key == "_spdisplays_pixels") }) { continue }
                properties.append(.init(key: key, label: name, value: shown))
            }
        }
        var node = HardwareNode(id: id, name: name, properties: properties, children: children.isEmpty ? nil : children)
        node.symbol = thing ? symbol : nil
        node.address = item["device_address"] as? String
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
        let bare = stripped(String(s)).0
        return names[bare] ?? systemText(key) ?? titled(spaced(bare))
    }

    /// System Information's own words for a key or a raw value ("spdisplays_metal4" is "Metal 4", "attrib_on" is "On"),
    /// in the user's language, from its reporters; nil where none has the word.
    static func systemText(_ raw: String) -> String? {
        for reporter in reporters {
            let shown = reporter.localizedString(forKey: raw, value: nil, table: nil)
            if shown != raw { return shown }
        }
        return nil
    }

    private static let reporters = ["Platform", "Memory", "Displays", "NVMe", "Storage", "Power", "USBHost", "Thunderbolt",
                                    "Bluetooth", "Network", "Audio", "Camera"]
        .compactMap { Bundle(path: "/System/Library/SystemProfiler/SP\($0)Reporter.spreporter") }

    /// Names for keys System Information has no word for, or one that would repeat another row's; in its Title Case.
    private static let names = [
        "pixelresolution": "Resolution", "resolution": "UI Looks Like", "ndrvs": "Connected Displays",
        "display-product-id": "Display Product ID", "display-vendor-id": "Display Vendor ID",
        "display-week": "Manufacture Week", "display-year": "Manufacture Year", "displayID": "Display ID",
        "battery_pcb_lot_code": "Battery PCB Lot Code", "os_loader_version": "OS Loader Version", "bsd_name": "BSD Name",
        "iocontent": "I/O Content", "ip_address": "IP Address", "platform_UUID": "Platform UUID",
        "USBDeviceKeyPowerAllocation": "Power Allocation", "SPMemoryDataType": "Size", "trim_support": "TRIM Support",
        "model-id": "Model ID", "UserVisible": "User Visible", "appPID": "App PID",
    ]

    /// A value for display: `spdisplays_supported` becomes "Supported", `true` becomes "Yes".
    static func text(_ value: Any) -> String {
        switch value {
        case let s as String:
            switch s {
            case "yes", "TRUE": return "Yes"
            case "no", "FALSE": return "No"
            default: break
            }
            // A raw token ("spdisplays_metal4", "ssd") has the system's word; a name ("Apple M5 Pro") stays as it is.
            if s.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil, let shown = systemText(s) { return shown }
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

    /// Title Case as System Information writes its labels: "free space" is "Free Space", "sleep on power button" is
    /// "Sleep on Power Button".
    private static func titled(_ s: String) -> String {
        let small: Set = ["a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to"]
        return s.split(separator: " ").enumerated().map { i, w in i > 0 && small.contains(String(w)) ? String(w) : capitalized(String(w)) }
            .joined(separator: " ")
    }

    /// Two `system_profiler` runs at once: every section at the mini level, but Bluetooth at the basic level, the only
    /// one that gives a device's address (for its actions).
    public static func capture(timeout: Duration = .seconds(30)) async throws -> [HardwareNode] {
        let bluetooth = "SPBluetoothDataType"
        async let mini = run(["-json", "-detailLevel", "mini"] + sections.map(\.type).filter { $0 != bluetooth }, timeout: timeout)
        async let basic = run(["-json", "-detailLevel", "basic", bluetooth], timeout: timeout)
        let root = try object(await mini).merging(try object(await basic)) { $1 }
        return parse(root: root)
    }

    /// Output is read on background tasks while the process runs.
    private static func run(_ arguments: [String], timeout: Duration) async throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = arguments
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
        return await stdout.value
    }
}
