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
    /// The path being scanned.
    private var scanningPath = ""
    private(set) var progress: DiskScanProgress?
    /// The bytes a volume scan will find, about: the volume's used space. Nil for a folder, which has no known total.
    private(set) var progressTotal: UInt64?
    /// Index path of the shown folder in `tree`.
    var focus: [Int] = []
    /// Index path of the table's selected item in `tree`, which the inspector shows.
    var selected: [Int]?
    private(set) var error: String?
    /// The item the Rename sheet is for, an index path in `tree`.
    var renaming: [Int]?
    /// A file to show in Quick Look.
    var quickLook: URL?
    /// What a file action that failed says: the alert's title and message.
    var actionFailure: (title: String, message: String)?
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
        scanningPath = root
        if case .volume(let volume) = target { progressTotal = volume.usedBytes ?? volume.totalBytes - volume.freeBytes } else { progressTotal = nil }
        tree = nil
        focus = []
        // An index path of the old tree names another item in the new one.
        selected = nil
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

    /// Choosing a target, and Disk's Show in Space: scans it unless its map is shown or being made.
    func open(_ target: Target) {
        let shown = isScanning ? scanningPath == target.path : tree?.rootPath == target.path
        self.target = target
        if !shown { scan() }
    }

    /// Moves the item to the Trash; the treemap drops it.
    func trash(_ indexPath: [Int]) {
        guard let path = path(indexPath) else { return }
        do {
            try FileManager.default.trashItem(at: URL(filePath: path), resultingItemURL: nil)
        } catch {
            actionFailure = ("Cannot Move to Trash", "\(URL(filePath: path).lastPathComponent): \(error.localizedDescription)")
            return
        }
        tree?.remove(at: indexPath)
        // Index paths after the dropped item shift by one; paths inside it are gone.
        selected = selected.flatMap { Self.shifted($0, removing: indexPath) }
        focus = Self.shifted(focus, removing: indexPath) ?? Array(indexPath.dropLast())
    }

    func rename(_ indexPath: [Int], to name: String) {
        guard let path = path(indexPath) else { return }
        let url = URL(filePath: path)
        do {
            try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name))
        } catch {
            actionFailure = ("Cannot Rename", "\(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        tree?.rename(at: indexPath, to: name)
    }

    /// The index path once `removed` is gone; nil when it was inside the removed item.
    private static func shifted(_ path: [Int], removing removed: [Int]) -> [Int]? {
        let depth = removed.count - 1
        guard path.count > depth, path.prefix(depth) == removed.prefix(depth), path[depth] >= removed[depth] else { return path }
        if path[depth] == removed[depth] { return nil }
        var path = path
        path[depth] -= 1
        return path
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
