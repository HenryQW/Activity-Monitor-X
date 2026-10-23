import AMXCore
import SwiftUI

/// What the title pill shows before the title: the screen's sidebar symbol, a group's symbol in its colour, or a pinned
/// app's own icon.
enum TitleIcon {
    case symbol(String, Color? = nil)
    case app(AppKey)
}

/// The detail area (which the toolbar spans) is narrow: the title pill shows its icon only.
private struct NarrowDetailKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var narrowDetail: Bool {
        get { self[NarrowDetailKey.self] }
        set { self[NarrowDetailKey.self] = newValue }
    }
}

extension View {
    /// The screen's title and subtitle: the window keeps them (VoiceOver, the Window menu), and the toolbar shows them
    /// in a glass pill at the leading side of the content column, after the screen's icon. The system title is removed
    /// in `MainWindow`, so the title shows once.
    func screenTitle(_ title: String, subtitle: Text? = nil, icon: TitleIcon) -> some View {
        navigationTitle(title)
            .navigationSubtitle(subtitle ?? Text(""))
            .toolbar {
                ToolbarItem(placement: .navigation) { TitlePill(title: title, subtitle: subtitle, icon: icon) }
                    // One glass, the pill's own: the item's shared capsule would put glass on glass.
                    .sharedBackgroundVisibility(.hidden)
            }
    }
}

private struct TitlePill: View {
    let title: String
    let subtitle: Text?
    let icon: TitleIcon
    @Environment(\.narrowDetail) private var narrow
    @Environment(ToolbarFit.self) private var fit

    var body: some View {
        HStack(spacing: Layout.inset) {
            image.frame(width: 20, height: 20).accessibilityHidden(true)
            if !narrow {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline).lineLimit(1)
                    subtitle?.font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                // A long group or app name truncates, so it never pushes toolbar items into the overflow.
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .floatingCapsule(padding: Layout.padding)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { if abs(fit.pill - $0) >= 1 { fit.pill = $0 } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .help(title)
    }

    @ViewBuilder private var image: some View {
        switch icon {
        case .symbol(let name, let color):
            Image(systemName: name).font(.title3).foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        case .app(let app):
            Image(nsImage: AppIcon.image(for: app)).resizable()
        }
    }
}
