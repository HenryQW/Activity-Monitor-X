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
        HStack(spacing: Layout.gap) {
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

/// The name a pinned app shows. A process outside an app bundle (an XPC service) is named by its executable, which can be
/// a truncated bundle ID; its bundle's display name says more. The executable name stays when no bundle names it.
@MainActor
enum AppName {
    private static var cache: [String: String] = [:]
    private static let suffixes = [".app", ".xpc", ".appex"]

    static func display(_ app: AppKey, history: HistoryModel) -> String {
        guard !app.key.hasPrefix("/") else { return app.name }
        if let hit = cache[app.key] { return hit }
        let name = bundleName(app, history: history) ?? app.name
        cache[app.key] = name
        return name
    }

    private static func bundleName(_ app: AppKey, history: HistoryModel) -> String? {
        guard let pool = try? history.openPool(), let path = try? HistoryReader(pool: pool).executablePath(ofBare: app.key) else { return nil }
        let parts = path.split(separator: "/")
        let bundle = parts.lastIndex { part in suffixes.contains { part.hasSuffix($0) } }
            .flatMap { Bundle(path: "/" + parts[...$0].joined(separator: "/")) }
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
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
        if cache.count >= 512 { cache.removeAll() }
        cache[app.key] = image
        return image
    }
}
