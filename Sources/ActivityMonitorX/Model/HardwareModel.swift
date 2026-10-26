import AMXCore
import Foundation
import Observation
import os

/// The Hardware screen's one `system_profiler` capture: read on the first open of the screen and on Refresh only.
@Observable @MainActor
final class HardwareModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "hardware")

    private(set) var nodes: [HardwareNode] = []
    private(set) var rows: [HardwareRow] = []
    private(set) var chip: ChipInfo?
    /// The startup volume, then the external drives' volumes (no network mounts); read apart from the capture, as the
    /// read can block on a dead network mount.
    private(set) var volumes: [VolumeInfo] = []
    private(set) var state: LoadState = .loading
    private(set) var capturedAt: Date?
    /// Expanded inventory rows; the sections on the first capture.
    var expanded: Set<String> = []
    /// The inventory row the inspector shows.
    var selected: HardwareRow.ID?
    /// The board part clicked last: of the parts that show the selected row (the clusters share one), it has the outline.
    var clickedPart: BoardPart?
    /// The row a board click asks the table to scroll to; the table clears it.
    var reveal: HardwareRow.ID?
    /// Read once per capture, not on each 2 s reading: the GPU core count, the memory type and each board part's row.
    private(set) var gpuCores: Int?
    private(set) var dimmType: String?
    private(set) var partRows: [(part: BoardPart, row: HardwareRow.ID)] = []
    /// `expanded` before the search began; nil while there is no search.
    private var expandedBeforeSearch: Set<String>?

    /// Not a child of the screen's task: leaving the screen does not cancel a capture, so a reopen finds its result.
    private var capture: Task<Void, Never>?
    private let volumeSource: VolumeSource

    init(volumeSource: VolumeSource) { self.volumeSource = volumeSource }

    /// Opens the rows that hold a match of `query`, over the rows open before the search; they come back when it ends.
    func expand(for query: String) {
        if query.isEmpty {
            if let saved = expandedBeforeSearch { expanded = saved }
            expandedBeforeSearch = nil
        } else {
            let saved = expandedBeforeSearch ?? expanded
            expandedBeforeSearch = saved
            expanded = saved.union(HardwareRow.filter(rows, query: query).opened)
        }
    }

    /// Opens rows, also under a search, so they stay open when it ends.
    func open(_ ids: [String]) {
        expanded.formUnion(ids)
        expandedBeforeSearch?.formUnion(ids)
    }

    /// First open only; later opens show what the last capture read.
    func loadOnce() async {
        if capture == nil, capturedAt == nil, state == .loading { await refresh() } else { await capture?.value }
    }

    /// One capture at a time: a Refresh during a capture waits for it.
    func refresh() async {
        readStartup()
        let task = capture ?? Task { await read() }
        capture = task
        await task.value
        if capture == task { capture = nil }
    }

    /// Usage 0–100 per logical CPU and of the GPU, read every 2 s while the screen shows (`sampleLive`).
    private(set) var cpuUsage: [Double] = []
    private(set) var gpuUsage: Double?
    /// Memory used, 0–100 of the installed memory.
    private(set) var memoryUsage: Double?
    /// The battery's charge; nil on a Mac with no battery.
    private(set) var charge: PowerReading.Battery?
    /// Brightness 0–1 by display row, for the displays that report it (the built-in one).
    private(set) var brightness: [HardwareRow.ID: Double] = [:]
    /// Each display row's display ID, from the capture.
    private var displayIDs: [(row: HardwareRow.ID, id: UInt32)] = []

    /// The screen's `.task`: ends, and so stops reading, when the screen goes; pauses while the window is not on screen.
    func sampleLive() async {
        let load = CoreLoad()
        cpuUsage = []
        while !Task.isCancelled {
            if MainWindowRef.windowShown {
                cpuUsage = load.read()
                gpuUsage = GPUReader.deviceUtilization()
                if let chip, chip.memory > 0, let memory = HostReader.memory() { memoryUsage = Double(memory.used) / Double(chip.memory) * 100 }
                charge = PowerReader.read().battery
                brightness = Dictionary(uniqueKeysWithValues: displayIDs.compactMap { d in DisplayBrightness.read(d.id).map { (d.row, $0) } })
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// The first value of `key` in the tree, depth first.
    func value(_ key: String) -> String? { values(key).first?.value }

    /// Every value of `key` in the tree, depth first, with its node's title.
    func values(_ key: String) -> [(name: String, value: String)] { Self.values(key, in: nodes) }

    private func read() async {
        chip = ChipInfo.current()
        state = .loading
        Self.log.notice("capture: start")
        let start = ContinuousClock.now
        do {
            let nodes = try await HardwareInventory.capture()
            var seen: [String: Int] = [:]
            rows = nodes.map { Self.row($0, seen: &seen) }
            if capturedAt == nil { expanded = Set(rows.map(\.id)) }
            self.nodes = nodes
            gpuCores = value("sppci_cores").flatMap { Int($0) }
            dimmType = value("dimm_type")
            partRows = parts()
            displayIDs = displays.compactMap { d in property("_spdisplays_displayID", of: d.row).flatMap(UInt32.init).map { (d.row.id, $0) } }
            capturedAt = Date()
            state = nodes.isEmpty ? .empty : .ready
            Self.log.notice("capture: \(nodes.count) sections in \(ContinuousClock.now - start, privacy: .public)")
        } catch HardwareError.timedOut {
            state = .failed("System Information did not answer in time.")
            Self.log.error("capture: timed out")
        } catch HardwareError.failed(let status, let line) {
            state = .failed(line.isEmpty ? "System Information exited with status \(status)." : line)
            Self.log.error("capture: exit \(status, privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
            Self.log.error("capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readStartup() {
        Task {
            let all = await volumeSource.read().volumes
            volumes = all.filter { $0.mountPoint == "/" } + all.filter { !$0.isInternal && !$0.bsdName.isEmpty }
            partRows = parts()
        }
    }

    /// Sibling nodes can share a name (two identical hubs), so a repeated id gets "#n".
    private static func row(_ node: HardwareNode, seen: inout [String: Int]) -> HardwareRow {
        let count = seen[node.id, default: 0]
        seen[node.id] = count + 1
        let id = count == 0 ? node.id : "\(node.id)#\(count)"
        let properties = node.properties.map { HardwareRow(id: "\(id)=\($0.key)", name: $0.label, value: $0.value, children: nil) }
        let nodes = (node.children ?? []).map { row($0, seen: &seen) }
        // A group of one child is that child, with the group's symbol where the child has none (a section's one unnamed
        // item); a group of one property shows the value on its own row.
        if properties.isEmpty, nodes.count == 1 {
            let child = nodes[0]
            return HardwareRow(id: child.id, name: child.name, value: child.value, children: child.children, symbol: child.symbol ?? node.symbol)
        }
        if nodes.isEmpty, properties.count == 1 {
            return HardwareRow(id: id, name: title(node.name), value: properties[0].value, children: nil, symbol: node.symbol)
        }
        let children = properties + nodes
        return HardwareRow(id: id, name: title(node.name), value: children.isEmpty ? "" : "\(children.count) items",
                           children: children.isEmpty ? nil : children, symbol: node.symbol)
    }

    /// Raw item names (`hardware_overview`) through the inventory's label; device names ("iPhone") as they are. Only
    /// "sp" goes, so `spbattery_information` and `sppower_information` stay apart.
    private static func title(_ name: String) -> String {
        guard name.contains("_"), name == name.lowercased() else { return name }
        return HardwareInventory.label(name.hasPrefix("sp") ? String(name.dropFirst(2)) : name)
    }

    private static func values(_ key: String, in nodes: [HardwareNode]) -> [(name: String, value: String)] {
        nodes.flatMap { node in (node.value(key).map { [(title(node.name), $0)] } ?? []) + values(key, in: node.children ?? []) }
    }
}
