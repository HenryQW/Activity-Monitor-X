import Darwin

public enum DiskScanError: Error, Equatable {
    /// The root cannot be opened: its path and errno.
    case cannotOpen(String, Int32)
}

/// Walks one volume below a root folder and keeps a bounded tree of the largest items.
public enum DiskScanner {
    /// Synchronous: the app runs it on its own thread. `shouldStop` and `progress` run
    /// every 1,024 entries; on stop the open folders close as they are and the tree is `partial`.
    public static func scan(_ root: String, limits: DiskScanLimits = .init(),
                            shouldStop: () -> Bool = { Task.isCancelled },
                            progress: (DiskScanProgress) -> Void = { _ in }) throws -> DiskTree {
        // Never download iCloud placeholders. The scan has no `await`, so it stays on this thread.
        let policy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                       IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, policy) }

        // No symlink follow, no mount crossing.
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(paths[0]) }
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            throw DiskScanError.cannotOpen(root, errno)
        }
        defer { fts_close(fts) }

        var tree = Builder(limits: limits)
        var entries = 0
        var partial = false
        errno = 0
        while let entry = fts_read(fts) {
            let e = entry.pointee
            let info = Int32(e.fts_info)
            if info == FTS_DP { tree.close(); continue }
            if e.fts_level == 0, info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                throw DiskScanError.cannotOpen(root, e.fts_errno)
            }
            let name = e.fts_level == 0 ? root
                : String(cString: UnsafeRawPointer(entry.pointer(to: \.fts_name)!).assumingMemoryBound(to: CChar.self))
            switch info {
            case FTS_D:
                if e.fts_statp.pointee.st_flags & UInt32(SF_DATALESS) != 0 { fts_set(fts, entry, FTS_SKIP) }
                tree.open(String(cString: e.fts_path), name: name)
            case FTS_DNR, FTS_ERR:
                // An unreadable folder comes as FTS_D, then FTS_DNR with no FTS_DP.
                if tree.frames.count == Int(e.fts_level) + 1 { tree.drop() }
                if e.fts_errno == EPERM || e.fts_errno == EACCES { tree.refuse(String(cString: e.fts_path), name: name) }
            case FTS_NS:
                break
            default:
                let st = e.fts_statp.pointee
                // Counted once per (st_dev, st_ino). APFS folders have st_nlink > 1, so regular files only.
                // This set is not under the node cap: a normal Mac has few hard links.
                let again = info == FTS_F && st.st_nlink > 1
                    && !tree.linked.insert(FileID(dev: st.st_dev, ino: st.st_ino)).inserted
                tree.leaf(name: name, size: again ? 0 : UInt64(st.st_blocks) * 512)
            }
            entries += 1
            if entries % 1024 == 0 {
                progress(DiskScanProgress(items: entries, bytes: tree.bytes, folder: tree.frames.last?.path ?? root))
                if shouldStop() { partial = true; break }
            }
        }
        // A NULL with errno set is a walk error, not the end: the sizes then miss what was not read.
        if !partial, errno != 0 { partial = true }
        while !tree.frames.isEmpty { tree.close() }
        return DiskTree(rootPath: root, root: tree.root!, refused: tree.refused, refusedCount: tree.refusedCount,
                        partial: partial, simplified: tree.simplified)
    }
}

private struct FileID: Hashable {
    let dev: Int32
    let ino: UInt64
}

/// A stack of open folders. `live` counts the nodes alive (kept children, open folders, `smaller` nodes) and
/// never passes `maxNodes`: an open folder reserves two nodes, itself and its `smaller`.
private struct Builder {
    typealias Node = DiskTree.Node

    struct Frame {
        let path: String
        var node: Node
        /// False when the cap was reached at open: everything inside folds, and so does the folder.
        let counted: Bool
        var smallerSize: UInt64 = 0
        var smallerItems = 0
    }

    let limits: DiskScanLimits
    var frames: [Frame] = []
    var live = 0
    var root: Node?
    var linked = Set<FileID>()
    var refused: [String] = []
    var refusedCount = 0
    var simplified = false
    var bytes: UInt64 = 0

    mutating func open(_ path: String, name: String) {
        let counted = (frames.last?.counted ?? true) && live + 2 <= limits.maxNodes
        if counted { live += 2 } else { simplified = true }
        frames.append(Frame(path: path, node: Node(name: name, kind: .folder, size: 0, items: 1, children: [], count: 1),
                            counted: counted))
    }

    /// Removes the top folder, which has no content.
    mutating func drop() {
        if frames.removeLast().counted { live -= 2 }
    }

    mutating func close() {
        var frame = frames.removeLast()
        guard frame.counted else { return add(frame.node, keep: false) }
        live -= 2 + frame.node.children.reduce(0) { $0 + $1.count }
        if frame.smallerItems > 0 {
            frame.node.children.append(Node(name: "\(frame.smallerItems) smaller items", kind: .smaller,
                                            size: frame.smallerSize, items: frame.smallerItems, children: [], count: 1))
        }
        frame.node.children.sort { $0.size > $1.size }
        frame.node.count = 1 + frame.node.children.reduce(0) { $0 + $1.count }
        add(frame.node, keep: true)
    }

    mutating func leaf(name: String, size: UInt64) {
        bytes += size
        add(Node(name: name, kind: .file, size: size, items: 1, children: [], count: 1), keep: true)
    }

    mutating func refuse(_ path: String, name: String) {
        if refused.count < 200 { refused.append(path) }
        refusedCount += 1
        add(Node(name: name, kind: .refused, size: 0, items: 1, children: [], count: 1), keep: true)
    }

    /// Adds a node not counted in `live` to the top folder. Folds it at once when the per-folder rule or the
    /// cap would, so the per-folder result does not depend on scan order.
    private mutating func add(_ node: Node, keep: Bool) {
        guard let top = frames.indices.last else { root = node; return }
        frames[top].node.size += node.size
        frames[top].node.items += node.items
        guard frames[top].counted else { return }
        if keep, node.kind == .refused || node.size >= limits.minNodeBytes {
            if live + node.count <= limits.maxNodes {
                live += node.count
                frames[top].node.children.append(node)
                guard frames[top].node.children.count > limits.keepPerFolder else { return }
                let smallest = frames[top].node.children.indices.min {
                    frames[top].node.children[$0].size < frames[top].node.children[$1].size
                }!
                return fold(frames[top].node.children.remove(at: smallest), into: top, wasLive: true)
            }
            simplified = true
        }
        fold(node, into: top, wasLive: false)
    }

    private mutating func fold(_ node: Node, into top: Int, wasLive: Bool) {
        if wasLive { live -= node.count }
        frames[top].smallerSize += node.size
        frames[top].smallerItems += node.items
    }
}
