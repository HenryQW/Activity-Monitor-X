import Foundation
import Testing

@testable import AMXCore

struct HardwareInventoryTests {
    private func fixture() throws -> [HardwareNode] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/system-profiler-mini.json")
        return try HardwareInventory.parse(Data(contentsOf: url))
    }

    private func keys(_ node: HardwareNode) -> [String] {
        node.properties.map(\.key) + (node.children ?? []).flatMap(keys)
    }

    @Test func parseBuildsSections() throws {
        let tree = try fixture()
        #expect(tree.map(\.name) == ["Hardware", "Graphics and Displays", "Power", "Bluetooth"])
        #expect(tree[0].children?.first?.value("chip_type") == "Apple M0")
        let gpu = try #require(tree[1].children?.first)
        #expect(gpu.children?.map(\.name) == ["Test Display"])
        #expect(gpu.children?.first?.id == "Graphics and Displays/Apple M0 GPU/Test Display")
        #expect(tree[3].children?.flatMap { $0.children ?? [] }.map(\.name).contains("Test Phone") == true)
    }

    @Test func identifiersAreDropped() throws {
        let all = try fixture().flatMap(keys).map { $0.lowercased() }
        #expect(all.count > 10)
        for bad in ["serial", "uid", "udid", "unique", "address"] {
            #expect(all.allSatisfy { !$0.contains(bad) }, "\(bad)")
        }
    }

    @Test func labelsAndText() {
        #expect(HardwareInventory.label("spdisplays_vendor") == "Vendor")
        #expect(HardwareInventory.label("chip_type") == "Chip type")
        #expect(HardwareInventory.label("_spdisplays_resolution") == "Resolution")
        #expect(HardwareInventory.text("spdisplays_supported") == "Supported")
        #expect(HardwareInventory.text(true) == "Yes")
        #expect(HardwareInventory.text(42) == "42")
    }

    @Test func builtInDisplayIsNamedByItsType() throws {
        let json = #"{"SPDisplaysDataType":[{"_name":"GPU","spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_display_type":"spdisplays_built-in-liquid-retina-xdr"},{"_name":"External"}]}]}"#
        let displays = try #require(HardwareInventory.parse(Data(json.utf8)).first?.children?.first?.children)
        #expect(displays.map(\.name) == ["Built-in Liquid Retina XDR Display", "External"])
        #expect(HardwareInventory.displayType("spdisplays_unknown-panel") == "Unknown-panel")
    }

    @Test func repeatedDisplayFactsShowOnce() throws {
        let json = #"{"SPDisplaysDataType":[{"_name":"GPU","spdisplays_ndrvs":[{"_name":"Monitor","_spdisplays_pixels":"4256 x 2394","_spdisplays_resolution":"2128 x 1197 @ 60.00Hz","spdisplays_pixelresolution":"4256 x 2394","spdisplays_resolution":"2128 x 1197 @ 60.00Hz","spdisplays_main":"spdisplays_yes","spdisplays_online":"spdisplays_yes"}]}]}"#
        let display = try #require(HardwareInventory.parse(Data(json.utf8)).first?.children?.first?.children?.first)
        #expect(display.properties.map(\.label) == ["Pixels", "Resolution", "Main", "Online"])
    }

    /// Bluetooth devices that are not connected are grouped apart, ports with nothing plugged in are left out, and things get
    /// symbols (values and groups do not).
    @Test func connectedGroupsEmptyPortsAndSymbols() throws {
        let json = #"""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
          "device_connected":[{"Mouse A":{"device_minorType":"Mouse"}}],
          "device_not_connected":[{"Keys B":{"device_minorType":"Keyboard"}},{"Phone C":{}}]}],
         "SPPowerDataType":[{"_name":"sppower_battery_information","sppower_cycle":"8"},{"_name":"sppower_ac_charger_information","sppower_watts":"96"}],
         "SPUSBHostDataType":[{"_name":"USB 3.1 Bus"},{"_name":"USB 4.0 Bus","_items":[{"_name":"USB DISK"}]}],
         "SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"receptacle_status_key":"receptacle_no_devices_connected"}}]}
        """#
        let all = try HardwareInventory.parse(Data(json.utf8))
        #expect(all.map(\.name) == ["Power", "USB", "Bluetooth"])
        #expect(all[0].symbol == "battery.100" && all[0].children?.map(\.symbol) == [nil, nil], "raw-named sets of values have no symbol")
        let tree = Array(all.dropFirst())
        let usb = try #require(tree.first)
        #expect(usb.children?.map(\.name) == ["USB 4.0 Bus"])
        #expect(usb.symbol == "cable.connector")
        let devices = try #require(tree[1].children?.first?.children)
        #expect(devices.map(\.name) == ["Controller properties", "Mouse A", "Not Connected"])
        #expect(devices.map(\.symbol) == [nil, "computermouse", nil], "a set of values and a group have no symbol")
        #expect(devices[2].children?.map(\.symbol) == ["keyboard", "dot.radiowaves.left.and.right"])
    }

    @Test func processorsText() {
        let clusters: [ChipInfo.Cluster] = [.init(name: "Super", cores: 5), .init(name: "Performance", cores: 10)]
        #expect(HardwareInventory.processors("proc 15:5:10:0", clusters: clusters) == "15 cores (5 Super, 10 Performance)")
        #expect(HardwareInventory.processors("proc ?", clusters: clusters) == "proc ?")
    }

    @Test func chipInfoMatchesSysctl() {
        let chip = ChipInfo.current()
        #expect(!chip.clusters.isEmpty && chip.clusters.allSatisfy { !$0.name.isEmpty && $0.cores > 0 })
        #expect(chip.memory == ProcessInfo.processInfo.physicalMemory)
        // Apple silicon has no SMT, so the clusters' cores are all the logical CPUs.
        #expect(chip.clusters.reduce(0) { $0 + $1.cores } == ProcessInfo.processInfo.processorCount)
    }

    @Test func captureSmoke() async throws {
        let start = ContinuousClock.now
        let tree = try await HardwareInventory.capture()
        #expect(ContinuousClock.now - start < .seconds(10))
        #expect(tree.contains { $0.name == "Hardware" })
    }

    @Test func rowFilterKeepsParentsOfMatches() {
        let leaf = { (id: String, value: String) in HardwareRow(id: id, name: id, value: value, children: nil) }
        let usb = HardwareRow(id: "USB", name: "USB", value: "1 items", children: [
            HardwareRow(id: "Hub", name: "Hub", value: "2 items", children: [leaf("Speed", "480 Mb/s"), leaf("Vendor", "Apple")]),
        ])
        let rows = [usb, leaf("Model", "Mac")]
        #expect(HardwareRow.filter(rows, query: "").rows == rows)
        #expect(HardwareRow.filter(rows, query: "zzz").rows.isEmpty)
        // A parent's value is its count, not data.
        #expect(HardwareRow.filter(rows, query: "items").rows.isEmpty)
        let nested = HardwareRow.filter(rows, query: "apple")
        #expect(nested.rows.map(\.id) == ["USB"])
        #expect(nested.rows[0].children?[0].children?.map(\.id) == ["Vendor"])
        #expect(nested.opened == ["USB", "Hub"])
        // A matching row keeps all its rows.
        #expect(HardwareRow.filter(rows, query: "hub").rows[0].children?[0].children?.count == 2)
        #expect(HardwareRow.path(to: "Vendor", in: rows).map(\.id) == ["USB", "Hub", "Vendor"])
    }

    @Test func rowsHoldingAKey() {
        let leaf = { (id: String, value: String) in HardwareRow(id: id, name: id, value: value, children: nil) }
        let data = HardwareRow(id: "Storage/Data", name: "Data", value: "", children: [leaf("Storage/Data=mount_point", "/System/Volumes/Data")])
        let root = HardwareRow(id: "Storage/HD", name: "HD", value: "", children: [leaf("Storage/HD=mount_point", "/")])
        let rows = [HardwareRow(id: "Storage", name: "Storage", value: "", children: [data, root]), leaf("Model=mount_point", "/")]
        #expect(HardwareRow.rows(holding: "mount_point", in: rows).map(\.row.id) == ["Storage/Data", "Storage/HD"])
        // A key that only ends like another ("mount_point" in "remount_point") is not that key.
        #expect(HardwareRow.rows(holding: "point", in: rows).isEmpty)
        let found = HardwareRow.rows(holding: "mount_point", value: "/", in: rows)
        #expect(found.map(\.row.id) == ["Storage/HD"])
        #expect(found.first?.property.id == "Storage/HD=mount_point")
    }

    @Test func displayResolution() {
        #expect(HardwareInventory.resolution("1512 x 982 @ 120.00Hz") == "1512 x 982, 120 Hz")
        #expect(HardwareInventory.resolution("1920 x 1080 @ 59.94Hz") == "1920 x 1080, 59.94 Hz")
        #expect(HardwareInventory.resolution("1920 x 1080") == "1920 x 1080")
    }
}
