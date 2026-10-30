import AppKit
import SwiftUI

/// Reveals a file or folder in Finder, selected in its parent.
struct ShowInFinderButton: View {
    var title = "Show in Finder"
    let path: String
    let help: String

    var body: some View {
        Button(title, systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        }
        .help(help)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
