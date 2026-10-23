import AppKit
import SwiftUI

/// The terminal apps Open in Terminal can use; the Settings pop-up lists the installed ones.
enum TerminalApp {
    static let key = "terminalApp"
    static let defaultID = "com.apple.Terminal"
    private static let known = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                                "com.github.wez.wezterm", "org.alacritty", "net.kovidgoyal.kitty", "co.zeit.hyper"]

    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static var installed: [(id: String, name: String)] {
        known.compactMap { id in url(id).map { (id, FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")) } }
    }
}

/// Shared by the table and the treemap; empty for grouped small items, which have no one path. A Finder-like set in
/// groups: open, show, copy, change. Moving to the Trash asks nothing, as in Finder: the Trash can put the item back.
struct DiskItemMenu: View {
    @Environment(DiskMapModel.self) private var model
    @AppStorage(TerminalApp.key) private var terminal = TerminalApp.defaultID
    let id: [Int]

    var body: some View {
        content.labelStyle(.titleAndIcon)
    }

    /// Without the label style, a menu drops the icons.
    @ViewBuilder private var content: some View {
        if let path = model.path(id) {
            let url = URL(filePath: path)
            let isFolder = model.tree?[id].kind == .folder
            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                .help("Open the item with its default app")
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            if !apps.isEmpty {
                Menu("Open With", systemImage: "app.badge") {
                    ForEach(apps, id: \.self) { app in
                        Button { NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init()) } label: {
                            Text(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""))
                            Image(nsImage: Self.icon(app))
                        }
                    }
                }
                .help("Open the item with another app")
            }
            Button("Quick Look", systemImage: "eye") { model.quickLook = url }
                .help("Preview the item")
            Divider()
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .help("Show the item in Finder")
            Button("Get Info", systemImage: "info.circle") { Self.getInfo(path) }
                .help("Open the Finder info window of the item")
            Button("Open in Terminal", systemImage: "terminal") { openInTerminal(isFolder ? url : url.deletingLastPathComponent()) }
                .help(isFolder ? "Open the folder in the terminal app chosen in Settings" : "Open the folder of the file in the terminal app chosen in Settings")
            Divider()
            Button("Copy Path", systemImage: "doc.on.doc") { Self.copy(path) }
                .help("Copy the path of the item")
            Button("Copy Name", systemImage: "textformat") { Self.copy(url.lastPathComponent) }
                .help("Copy the name of the item")
            Divider()
            Button("Rename…", systemImage: "pencil") { model.renaming = id }
                .help("Change the name of the item")
            Button("Move to Trash", systemImage: "trash") { model.trash(id) }
                .help("Move the item to the Trash. The Trash can put it back.")
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func icon(_ app: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// Finder's own Show Info service: no AppleScript.
    private static func getInfo(_ path: String) {
        let board = NSPasteboard(name: .init("com.henryqw.activitymonitorx.info"))
        board.clearContents()
        board.setPropertyList([path], forType: .init("NSFilenamesPboardType"))
        NSPerformService("Finder/Show Info", board)
    }

    private func openInTerminal(_ folder: URL) {
        guard let app = TerminalApp.url(terminal) else {
            model.actionFailure = ("Cannot Open in Terminal", "The terminal app chosen in Settings is not installed.")
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: .init()) { _, error in
            guard let error else { return }
            Task { @MainActor in model.actionFailure = ("Cannot Open in Terminal", error.localizedDescription) }
        }
    }
}

/// The name field of Rename…: the sheet's Rename button is the default action.
struct DiskRenameSheet: View {
    let model: DiskMapModel
    let id: [Int]
    private let _name: State<String>

    init(model: DiskMapModel, id: [Int]) {
        self.model = model
        self.id = id
        _name = State(initialValue: model.tree?[id].name ?? "")
    }

    private var valid: Bool {
        let name = _name.wrappedValue
        return !name.isEmpty && !name.contains("/") && name != model.tree?[id].name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.headline)
            TextField("Name", text: Binding(get: { _name.wrappedValue }, set: { _name.wrappedValue = $0 }))
                .frame(width: 320)
                .help("The new name of the item")
                .onSubmit(done)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.renaming = nil }
                    .keyboardShortcut(.cancelAction)
                    .help("Close without renaming")
                Button("Rename", action: done)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
                    .help("Rename the item to the new name")
            }
        }
        .padding()
    }

    private func done() {
        guard valid else { return }
        model.renaming = nil
        model.rename(id, to: _name.wrappedValue)
    }
}
