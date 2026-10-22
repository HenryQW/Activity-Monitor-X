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
}
