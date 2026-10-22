import AMXCore
import Foundation
import Observation
import os

/// One row of the inventory table: a node with its properties, then its child nodes, as children.
struct HardwareRow: Identifiable {
    let id: String
    let name: String
    let value: String
    let children: [HardwareRow]?
}

/// The Hardware screen's one `system_profiler` capture: read on the first open of the screen and on Refresh only.
@Observable @MainActor
final class HardwareModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "hardware")

    private(set) var nodes: [HardwareNode] = []
    private(set) var rows: [HardwareRow] = []
    private(set) var chip: ChipInfo?
    /// The startup volume, for the storage bar; read apart from the capture, as it can block on a dead network mount.
    private(set) var startup: VolumeInfo?
    private(set) var state: LoadState = .loading
    private(set) var capturedAt: Date?
    /// Expanded inventory rows; the sections on the first capture.
    var expanded: Set<String> = []

    /// Not a child of the screen's task: leaving the screen does not cancel a capture, so a reopen finds its result.
    private var capture: Task<Void, Never>?
    private let volumeSource: VolumeSource

    init(volumeSource: VolumeSource) { self.volumeSource = volumeSource }

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
        Task { startup = await volumeSource.read().volumes.first { $0.mountPoint == "/" } }
    }

    /// Sibling nodes can share a name (two identical hubs), so a repeated id gets "#n".
    private static func row(_ node: HardwareNode, seen: inout [String: Int]) -> HardwareRow {
        let count = seen[node.id, default: 0]
        seen[node.id] = count + 1
        let id = count == 0 ? node.id : "\(node.id)#\(count)"
        let properties = node.properties.map { HardwareRow(id: "\(id)=\($0.key)", name: $0.label, value: $0.value, children: nil) }
        let children = properties + (node.children ?? []).map { row($0, seen: &seen) }
        return HardwareRow(id: id, name: title(node.name), value: "", children: children.isEmpty ? nil : children)
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
