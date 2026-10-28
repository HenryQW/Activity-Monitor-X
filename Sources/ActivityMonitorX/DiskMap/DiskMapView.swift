import AMXCore
import AppKit
import QuickLook
import SwiftUI

/// The largest items under a volume or folder: a treemap beside a table of the same items, which is the accessible
/// path. The search filters the table by name; its selection is the inspector's. Content layer: no glass. The system asks
/// for protected folders on first access (M5-D9); the app does not pre-check them. Choosing a target scans it at once.
struct DiskMapView: View {
    @Environment(DiskMapModel.self) private var model
    @Environment(Selection.self) private var selection

    private static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    var body: some View {
        content
            .screenTitle("Disk", subtitle: Text(model.tree == nil ? "Space" : model.title), icon: .symbol("internaldrive"))
            .task { await model.loadVolumes() }
            .onChange(of: selection.refreshes) { if !model.isScanning { model.scan() } }
            .quickLookPreview(Bindable(model).quickLook)
            .sheet(item: Binding(get: { model.renaming.map(RenameTarget.init) }, set: { model.renaming = $0?.id })) {
                DiskRenameSheet(model: model, id: $0.id)
            }
            .alert(model.actionFailure?.title ?? "", isPresented: Binding(get: { model.actionFailure != nil }, set: { if !$0 { model.actionFailure = nil } })) {
                Button("OK") {}
            } message: {
                Text(model.actionFailure?.message ?? "")
            }
    }

    private struct RenameTarget: Identifiable {
        let id: [Int]
    }

    @ViewBuilder private var content: some View {
        if model.isScanning {
            scanning
        } else if let tree = model.tree {
            result(tree)
        } else if model.stopped {
            ContentUnavailableView("Stopped", systemImage: "stop.circle", description: Text("Click Rescan to start again."))
        } else if let error = model.error {
            ContentUnavailableView("Cannot Scan", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView {
                Label("Space", systemImage: "square.grid.3x3.square")
            } description: {
                Text("Choose a volume or folder to see what takes the space.")
            } actions: {
                // The screen's one action: prominent.
                Button("Choose Folder…") { DiskMapTargetMenu.choose(model) }
                    .buttonStyle(.borderedProminent)
                    .help("Choose a folder to scan")
            }
        }
    }

    /// Determinate for a volume (scanned bytes of the used space), else indeterminate.
    private var scanning: some View {
        VStack(spacing: 12) {
            let progress = model.progress
            if let total = model.progressTotal, total > 0 {
                ProgressView(value: Double(min(progress?.bytes ?? 0, total)), total: Double(total))
                    .accessibilityLabel("Scanning \(model.title)")
            } else {
                ProgressView().accessibilityLabel("Scanning \(model.title)")
            }
            HStack {
                Text(progress.map { "Scanning \(model.title)… \($0.items.formatted()) items, \(Metric.bytes(Double($0.bytes)))" } ?? "Scanning \(model.title)…")
                    .monospacedDigit()
                Button("Stop") { model.stop() }
                    .help("Stop the scan. Sizes stay partial.")
            }
            if let progress {
                Text(progress.folder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
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
            // Above the split view, not a safe area bar: its treemap and table sit in AppKit panes that take no safe
            // area, so a bar would put the treemap labels and the table header under the capsules.
            // The path is the one capsule: Show in Finder is in the item menu and the inspector's Path card, the details
            // are behind the toolbar's Info button.
            HStack {
                pathBar(tree)
                Spacer(minLength: 0)
            }
            .padding(Layout.inset)
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    TreemapCanvas(node: folder, base: focus, baseNames: focus.indices.map { tree[Array(focus.prefix($0 + 1))].name },
                                  selected: model.selected,
                                  label: "Disk map of \(focus.isEmpty ? model.title : folder.name), \(Metric.bytes(Double(folder.size)))",
                                  open: { model.focus = $0 })
                    FileKindLegend().padding(8)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                let rows = folder.children.enumerated().map { Row(id: focus + [$0.offset], node: $0.element) }
                table(NameSearch.filter(rows, query: selection.search) { [$0.node.name] }, total: folder.size)
                    .frame(minWidth: 340, idealWidth: 420, maxHeight: .infinity)
            }
            // The screen's footer (WIN-13) in its own row: the AppKit panes above take no safe area, so a bar would cover
            // the table's last rows and the treemap's labels.
            footer(tree, folder: folder)
                .frame(maxWidth: .infinity)
                .floatingBar()
                .padding(Layout.inset)
        }
    }

    /// The shown folder in small as the treemap draws it (one level, no labels), then its size, its items, its largest
    /// item and its share of the volume's used space, or of the scan for a folder (SP1).
    private func footer(_ tree: DiskTree, folder: DiskTree.Node) -> some View {
        let focus = model.focus
        let name = focus.isEmpty ? model.title : folder.name
        let largest = folder.children.first
        let whole: (size: Double, label: String) = if case .volume(let volume)? = model.target {
            (Double(volume.totalBytes - min(volume.freeBytes, volume.totalBytes)), "Of the volume used")
        } else {
            (Double(tree.root.size), "Of \(model.title)")
        }
        return ScreenFooter(figures: [
            FooterFigure(label: name, value: Metric.bytes(Double(folder.size)), help: "The size of \(name)"),
            FooterFigure(label: "Items", value: folder.items.formatted(), help: "The files and folders in \(name)"),
            FooterFigure(label: largest.map { "Largest, \(Metric.bytes(Double($0.size)))" } ?? "Largest", value: largest?.name ?? "None",
                         help: "The largest item in \(name)"),
            FooterFigure(label: whole.label, value: whole.size > 0 ? min(Double(folder.size) / whole.size, 1).formatted(.percent.precision(.fractionLength(0))) : "–",
                         help: "The share of \(name) in the space used"),
        ]) {
            GeometryReader { geometry in
                let cells = Treemap.cells(folder, in: CGRect(origin: .zero, size: geometry.size), depth: 1, minArea: 4)
                let kinds = TreemapCanvas.kinds(cells, node: folder, baseNames: focus.indices.map { tree[Array(focus.prefix($0 + 1))].name })
                Canvas { context, _ in TreemapCanvas.draw(cells, kinds: kinds, labels: false, in: &context) }
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel("\(name) summary")
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
                            .help("Open Privacy & Security settings to allow Full Disk Access")
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

    /// The scanned volume's drive by its kind, or a folder.
    private var rootSymbol: String {
        if case .volume(let volume)? = model.target { volume.isInternal ? "internaldrive" : "externaldrive" } else { "folder" }
    }

    /// One button per level from the scanned root to the focus: a level 2 capsule that fits its content; a path too long
    /// for the column scrolls inside it.
    private func pathBar(_ tree: DiskTree) -> some View {
        let focus = model.focus
        let path = HStack(spacing: Layout.inset) {
            ForEach(0...focus.count, id: \.self) { level in
                if level > 0 {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                // Each step is the thing it names, as a path control: the drive, then folders.
                Button(level == 0 ? model.title : tree[Array(focus.prefix(level))].name,
                       systemImage: level > 0 ? "folder" : rootSymbol) {
                    model.focus = Array(focus.prefix(level))
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .fontWeight(level == focus.count ? .semibold : nil)
                .help("Show this folder")
            }
        }
        // The folder's size and items are in the footer.
        return ViewThatFits(in: .horizontal) {
            path.fixedSize()
            ScrollView(.horizontal) { path }.scrollIndicators(.never)
        }
        .floatingCapsule()
    }

    // MARK: Table

    /// Identity is the index path: names can repeat ("3 smaller items" can also be a file's name).
    private struct Row: Identifiable {
        let id: [Int]
        let node: DiskTree.Node
    }

    private func table(_ rows: [Row], total: UInt64) -> some View {
        Table(rows, selection: Bindable(model).selected) {
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
            if ids.count == 1, let id = ids.first { DiskItemMenu(id: id) }
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

/// Toolbar: what to scan.
struct DiskMapTargetMenu: View {
    let model: DiskMapModel

    var body: some View {
        Menu {
            ForEach(model.volumes) { volume in
                Button(volume.name) { model.open(.volume(volume)) }
            }
            Divider()
            Button("Home Folder") { model.open(.folder(.homeDirectory)) }
            Button("Choose Folder…", action: choose)
        } label: {
            Label(model.target?.name ?? "Volume or Folder", systemImage: "internaldrive")
        }
        .labelStyle(.titleOnly)
        .help("Choose the volume or folder to scan")
    }

    private func choose() { Self.choose(model) }

    static func choose(_ model: DiskMapModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        let done = { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url { model.open(.folder(url)) }
        }
        if let window = MainWindowRef.window { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }
}

/// Toolbar: Rescan once a target is chosen (a choice scans at once); while a scan runs, Stop is beside its progress.
struct DiskMapScanButton: View {
    let model: DiskMapModel

    var body: some View {
        if !model.isScanning, let target = model.target {
            Button("Rescan") { model.scan() }
                .help("Scan \(target.name) again")
        }
    }
}
