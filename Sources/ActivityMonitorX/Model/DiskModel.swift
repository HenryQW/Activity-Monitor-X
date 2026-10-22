import AMXCore
import Foundation
import Observation
import os

/// The Disk screen's own readings, apart from amxd: rates of each physical disk every second, volumes every 30 s, disks
/// and their SMART health on start and on Refresh. Every read runs off the main actor.
@Observable @MainActor
final class DiskModel {
    private static let log = Logger(subsystem: AMX.bundleID, category: "disk")

    private(set) var volumes: [VolumeInfo] = []
    private(set) var containers: [APFSContainer] = []
    private(set) var disks: [PhysicalDisk] = []
    /// By BSD name; a disk without a SMART log (external) has none.
    private(set) var health: [String: NVMeHealth] = [:]
    /// By BSD name; a disk seen on one read only has none.
    private(set) var perDisk: [String: DiskRate] = [:]
    /// All physical disks together, one point a second, the last 300.
    private(set) var live: [(ts: Double, total: DiskRate)] = []
    private(set) var error: String?

    private let sampler = DiskSampler()
    private let volumeSource: VolumeSource

    init(volumeSource: VolumeSource) { self.volumeSource = volumeSource }

    /// Runs while the Disk screen is shown (its `.task`), so nothing is read while it is not; reads pause while the window
    /// is minimized, hidden or covered, as Live does. Each visit starts afresh.
    /// A volume read stuck on a dead network mount holds only its own loop.
    func run() async {
        live = []
        perDisk = [:]
        await sampler.reset()
        (disks, health) = await sampler.inventory()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.pollRates() }
            group.addTask { await self.pollVolumes() }
        }
    }

    /// Reads the disks, their health and the volumes again.
    func refresh() async {
        (disks, health) = await sampler.inventory()
        await readVolumes()
    }

    private func pollRates() async {
        while !Task.isCancelled {
            guard MainWindowRef.windowShown else {
                // The first rate after the pause covers 1 s, not the pause.
                await sampler.reset()
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let (ts, rates) = await sampler.rates()
            if let rates {
                perDisk = rates
                // A wall clock that stepped back starts the line again, so its times only rise.
                if let last = live.last?.ts, ts <= last { live = [] }
                live.append((ts, DiskMath.total(Array(rates.values))))
                live.removeFirst(max(0, live.count - 300))
            }
            error = rates?.isEmpty == true ? "No disk statistics are available." : nil
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func pollVolumes() async {
        repeat {
            if MainWindowRef.windowShown { await readVolumes() }
        } while (try? await Task.sleep(for: .seconds(30))) != nil
    }

    private func readVolumes() async {
        (volumes, containers) = await volumeSource.read()
        Self.log.debug("volume poll: \(self.volumes.count) volumes, \(self.containers.count) containers")
    }
}

/// Holds the one `DiskStatsReader` (not Sendable, it caches) on its own isolation domain.
private actor DiskSampler {
    private let reader = DiskStatsReader()
    private var previous: (counters: [UInt64: DiskCounters], uptime: Double)?

    func reset() { previous = nil }

    /// Rates since the previous read; nil on the first read after a reset.
    func rates() -> (ts: Double, rates: [String: DiskRate]?) {
        let counters = reader.read()
        let uptime = ProcessInfo.processInfo.systemUptime
        defer { previous = (counters, uptime) }
        guard let previous, uptime > previous.uptime else { return (Date().timeIntervalSince1970, nil) }
        return (Date().timeIntervalSince1970,
                DiskMath.rates(current: counters, previous: previous.counters, wall: uptime - previous.uptime))
    }

    func inventory() -> (disks: [PhysicalDisk], health: [String: NVMeHealth]) {
        let disks = reader.devices()
        var health: [String: NVMeHealth] = [:]
        for disk in disks { health[disk.bsdName] = NVMeHealth.read(bsdName: disk.bsdName) }
        return (disks, health)
    }
}
