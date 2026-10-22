import AMXCore
import AppKit
import SwiftUI

/// The largest items under a volume or folder: a treemap beside a table of the same items, which is the accessible
/// path. Content layer: no glass. The system asks for protected folders on first access (M5-D9); the app does not
/// pre-check them. No Move to Trash: a monitor does not delete files.
struct DiskMapView: View {
    @Environment(DiskMapModel.self) private var model
    @Environment(Selection.self) private var selection
    private let _selected = State<[Int]?>(initialValue: nil)

    private static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    var body: some View {
        content
            .navigationTitle("Disk Map")
            .navigationSubtitle(model.tree == nil ? "" : model.title)
            .task { await model.loadVolumes() }
            .onChange(of: selection.refreshes) { if !model.isScanning { model.scan() } }
            // An index path of the old tree names another item in the new one.
            .onChange(of: model.isScanning) { _selected.wrappedValue = nil }
    }

    @ViewBuilder private var content: some View {
        if model.isScanning {
            scanning
        } else if let tree = model.tree {
            result(tree)
        } else if model.stopped {
            ContentUnavailableView("Stopped", systemImage: "stop.circle", description: Text("Click Scan to start again."))
        } else if let error = model.error {
            ContentUnavailableView("Cannot Scan", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView {
                Label("Disk Map", systemImage: "square.grid.3x3.square")
            } description: {
                Text("Choose a volume or folder, then click Scan.")
            } actions: {
                Button("Choose Folder…") { DiskMapTargetMenu.choose(model) }
            }
        }
    }

    private var scanning: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let progress = model.progress {
                Text("\(progress.items.formatted()) items · \(Metric.bytes(Double(progress.bytes)))").monospacedDigit()
                Text(progress.folder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning…")
            }
            Button("Stop") { model.stop() }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Result

    private func result(_ tree: DiskTree) -> some View {
        let focus = model.focus
        let folder = tree[focus]
        return VStack(spacing: 0) {
            banners(tree)
            pathBar(tree, folder: folder)
            Divider()
            HSplitView {
                TreemapCanvas(node: folder, base: focus, selected: _selected.wrappedValue,
                              label: "Disk map of \(focus.isEmpty ? model.title : folder.name), \(Metric.bytes(Double(folder.size)))",
                              open: { model.focus = $0 }, path: model.path)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                table(folder.children.enumerated().map { Row(id: focus + [$0.offset], node: $0.element) }, total: folder.size)
                    .frame(minWidth: 340, idealWidth: 420, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func banners(_ tree: DiskTree) -> some View {
        if tree.refusedCount > 0 || tree.simplified || tree.partial {
            VStack(alignment: .leading, spacing: 8) {
                if tree.refusedCount > 0 {
                    Label("^[\(tree.refusedCount) folder](inflect: true) could not be read", systemImage: "lock")
                    DisclosureGroup("Folders") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(tree.refused, id: \.self) { Text($0) }
                                if tree.refusedCount > tree.refused.count {
                                    Text("and \(tree.refusedCount - tree.refused.count) more").foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        .frame(maxHeight: 120)
                    }
                    HStack {
                        Button("Open Full Disk Access Settings") { NSWorkspace.shared.open(Self.fullDiskAccess) }
                        Text("After you allow access, quit and reopen Activity Monitor X.").foregroundStyle(.secondary)
                    }
                }
                if tree.simplified {
                    Label("Small items are grouped to keep memory use low.", systemImage: "square.stack.3d.up")
                }
                if tree.partial {
                    Label("Scan stopped. Sizes are partial.", systemImage: "exclamationmark.triangle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            Divider()
        }
    }

    /// One button per level from the scanned root to the focus.
    private func pathBar(_ tree: DiskTree, folder: DiskTree.Node) -> some View {
        let focus = model.focus
        return HStack {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(0...focus.count, id: \.self) { level in
                        if level > 0 {
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Button(level == 0 ? model.title : tree[Array(focus.prefix(level))].name) {
                            model.focus = Array(focus.prefix(level))
                        }
                        .buttonStyle(.borderless)
                        .fontWeight(level == focus.count ? .semibold : nil)
                    }
                }
            }
            .scrollIndicators(.never)
            Text("\(folder.items.formatted()) items · \(Metric.bytes(Double(folder.size)))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: Table

    /// Identity is the index path: names can repeat ("3 smaller items" can also be a file's name).
    private struct Row: Identifiable {
        let id: [Int]
        let node: DiskTree.Node
    }

    private func table(_ rows: [Row], total: UInt64) -> some View {
        Table(rows, selection: _selected.projectedValue) {
            TableColumn("Name") { row in
                Label(row.node.name, systemImage: Self.symbol(row.node.kind))
                    .help(row.node.kind == .refused ? "Could not be read" : row.node.name)
            }
            TableColumn("Size") { row in
                Text(row.node.kind == .refused ? "Not readable" : Metric.bytes(Double(row.node.size))).monospacedDigit()
            }
            .width(min: 70, ideal: 84)
            .alignment(.trailing)
            TableColumn("Items") { Text($0.node.items.formatted()).monospacedDigit() }
                .width(min: 50, ideal: 70)
                .alignment(.trailing)
            TableColumn("% of Folder") { row in
                Text(total == 0 ? "–" : (Double(row.node.size) / Double(total)).formatted(.percent.precision(.fractionLength(1))))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: [Int].self) { ids in
            if ids.count == 1, let id = ids.first { DiskItemMenu(path: model.path(id)) }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first, model.tree?[id].kind == .folder { model.focus = id }
        }
    }

    private static func symbol(_ kind: DiskTree.Node.Kind) -> String {
        switch kind {
        case .folder: "folder"
        case .file: "doc"
        case .smaller: "square.stack.3d.up"
        case .refused: "lock"
        }
    }
}

/// Shared by the table and the treemap; empty for grouped small items, which have no one path.
struct DiskItemMenu: View {
    let path: String?

    var body: some View {
        if let path {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

/// Toolbar: what to scan.
struct DiskMapTargetMenu: View {
    let model: DiskMapModel

    var body: some View {
        Menu {
            ForEach(model.volumes) { volume in
                Button(volume.name) { model.target = .volume(volume) }
            }
            Divider()
            Button("Home Folder") { model.target = .folder(.homeDirectory) }
            Button("Choose Folder…", action: choose)
        } label: {
            Label(model.target?.name ?? "Volume or Folder", systemImage: "internaldrive")
        }
        .labelStyle(.titleOnly)
        .help("Volume or folder to scan")
    }

    private func choose() { Self.choose(model) }

    static func choose(_ model: DiskMapModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        let done = { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url { model.target = .folder(url) }
        }
        if let window = MainWindowRef.window { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }
}

/// Toolbar: Scan, or Stop while a scan runs.
struct DiskMapScanButton: View {
    let model: DiskMapModel

    var body: some View {
        if model.isScanning {
            Button("Stop") { model.stop() }
                .help("Stop the scan")
        } else {
            Button("Scan") { model.scan() }
                .buttonStyle(.borderedProminent)
                .help("Scan the volume or folder")
                .disabled(model.target == nil)
        }
    }
}
