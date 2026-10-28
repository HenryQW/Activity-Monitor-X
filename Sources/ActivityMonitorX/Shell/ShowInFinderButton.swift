import AppKit
import SwiftUI

/// Reveals a file or folder in the Finder, selected in its parent.
struct ShowInFinderButton: View {
    let path: String
    var help = ""

    var body: some View {
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        }
        .help(help)
    }
}
