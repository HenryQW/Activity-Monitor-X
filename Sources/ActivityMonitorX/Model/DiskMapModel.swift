import AMXCore
import Foundation
import Observation
import os
import Synchronization

/// One Disk Map scan at a time; its tree stays while the app runs and a new scan replaces it (M5-D10). Nothing from it
/// goes to the database or MCP, and paths are logged private.
@Observable @MainActor
final class DiskMapModel {
    enum Target: Hashable {
        case volume(VolumeInfo)
        case folder(URL)

        var name: String {
            switch self {
            case .volume(let volume): volume.name
            case .folder(let url): url == .homeDirectory ? "Home Folder" : FileManager.default.displayName(atPath: url.path)
            }
        }

        /// The startup volume's files are on its Data volume; "/" is the sealed system snapshot.
        var path: String {
            switch self {
            case .volume(let volume): volume.mountPoint == "/" ? "/System/Volumes/Data" : volume.mountPoint
            case .folder(let url): url.path
            }
        }
    }

    private static let log = Logger(subsystem: AMX.bundleID, category: "diskmap")

    var target: Target?
    private(set) var volumes: [VolumeInfo] = []
    private(set) var tree: DiskTree?
    /// The scanned target's name, the path bar's first level.
    private(set) var title = ""
    private(set) var progress: DiskScanProgress?
    /// Index path of the shown folder in `tree`.
    var focus: [Int] = []
    private(set) var error: String?
    private(set) var isScanning = false
    /// Stop was clicked; the scan's partial result shows when it arrives, unless a newer scan started.
    private(set) var stopped = false
    /// Bumped by each scan: progress and results of an older scan are dropped.
    private var generation = 0
    /// The running scan's; Stop and a newer scan set it.
    private var stopFlag: StopFlag?
    private let volumeSource: VolumeSource

    init(volumeSource: VolumeSource) { self.volumeSource = volumeSource }

    func loadVolumes() async {
        volumes = await volumeSource.read().volumes
    }

    /// On its own thread, not the cooperative pool: a TCC prompt or one huge folder can hold it in a syscall for long.
    func scan() {
        guard let target else { return }
        stopFlag?.set()
        generation += 1
        let generation = generation, root = target.path, flag = StopFlag()
        stopFlag = flag
        title = target.name
        tree = nil
        focus = []
        progress = nil
        error = nil
        stopped = false
        isScanning = true
        Task {
            let start = ContinuousClock.now
            let result = await withCheckedContinuation { continuation in
                let thread = Thread {
                    var shown = start
                    continuation.resume(returning: Result {
                        try DiskScanner.scan(root, shouldStop: flag.isSet, progress: { progress in
                            // Called every 1,024 entries, often hundreds of times a second.
                            let now = ContinuousClock.now
                            guard now - shown >= .milliseconds(250) else { return }
                            shown = now
                            Task { @MainActor in if generation == self.generation, self.isScanning { self.progress = progress } }
                        })
                    })
                }
                thread.qualityOfService = .utility
                thread.start()
            }
            finish(result, generation: generation, root: root, elapsed: ContinuousClock.now - start)
        }
    }

    /// Never waits for the scan thread, which a TCC prompt or one huge folder can hold in a syscall.
    func stop() {
        stopFlag?.set()
        stopFlag = nil
        isScanning = false
        progress = nil
        stopped = true
    }

    /// The item's file path; nil for grouped small items, which have no one path.
    func path(_ indexPath: [Int]) -> String? {
        guard let tree else { return nil }
        var node = tree.root, path = tree.rootPath
        for i in indexPath {
            node = node.children[i]
            if node.kind == .smaller { return nil }
            path = (path as NSString).appendingPathComponent(node.name)
        }
        return path
    }

    private func finish(_ result: Result<DiskTree, any Error>, generation: Int, root: String, elapsed: Duration) {
        guard generation == self.generation else { return }
        stopFlag = nil
        isScanning = false
        progress = nil
        switch result {
        case .success(let tree):
            self.tree = tree
            Self.log.notice("scanned \(root, privacy: .private) in \(elapsed.formatted(), privacy: .public): \(tree.root.count) nodes, \(tree.refusedCount) refused, partial \(tree.partial), simplified \(tree.simplified)")
        case .failure(DiskScanError.cannotOpen(_, let code)):
            error = "The folder cannot be read: \(String(cString: strerror(code)))."
            Self.log.error("cannot scan \(root, privacy: .private): errno \(code)")
        case .failure(let failure):
            error = failure.localizedDescription
            Self.log.error("cannot scan \(root, privacy: .private): \(failure.localizedDescription, privacy: .private)")
        }
    }
}

/// Set on the main actor, read by the scan thread.
private final class StopFlag: Sendable {
    private let value = Mutex(false)

    func set() { value.withLock { $0 = true } }
    func isSet() -> Bool { value.withLock { $0 } }
}
