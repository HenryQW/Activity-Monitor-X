import AMXCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An app row's name: its chart colour (top apps only), its icon, and a pin glyph when pinned.
struct AppLabel: View {
    let app: AppKey
    let color: Color?
    let pinned: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color ?? .clear).frame(width: 8, height: 8)
            Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
            Text(app.name).lineLimit(1).help(app.key)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
    }
}

/// Icons are looked up once per app: tables redraw every second in Live.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    /// The bundle's icon for an app path; a process without an app gets the generic executable icon.
    static func image(for app: AppKey) -> NSImage {
        if let image = cache[app.key] { return image }
        let image = app.key.hasPrefix("/") ? NSWorkspace.shared.icon(forFile: app.key) : NSWorkspace.shared.icon(for: .unixExecutable)
        cache[app.key] = image
        return image
    }
}
