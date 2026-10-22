import AMXCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An app row's name: its colour dot (`AppColorDot`; filled for the top apps and chosen colours), its icon, a pin glyph when pinned, and the `detail` that tells
/// it from an app of the same name (`AppKey.details(for:)`).
struct AppLabel: View {
    let app: AppKey
    let color: Color?
    let history: HistoryModel
    let pinned: Bool
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            AppColorDot(app: app, history: history, color: color)
            Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
            Text(app.name).lineLimit(1).help(app.key).layoutPriority(1)
            if let detail {
                Text(detail).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Icons are looked up once per app: tables redraw every second in Live.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    /// The bundle's icon for an app path; every command-line process (no bundle) gets the same generic executable icon.
    static func image(for app: AppKey) -> NSImage {
        if let image = cache[app.key] { return image }
        let image = app.key.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: app.key) : NSWorkspace.shared.icon(for: .unixExecutable)
        cache[app.key] = image
        return image
    }
}
