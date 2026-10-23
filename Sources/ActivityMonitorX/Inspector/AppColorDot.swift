import AMXCore
import SwiftUI

/// The app's colour dot, the one control for its chosen colour (D54): a click opens the colours and None; while the
/// pointer is on it, a chosen colour shows a cross, and only a click on the cross removes the colour. An app with no
/// colour shows a ring under the pointer.
struct AppColorDot: View {
    let app: AppKey
    let history: HistoryModel
    let color: Color?
    var size: CGFloat = 12
    private let _hover = State(initialValue: false)

    var body: some View {
        let chosen = history.appColors[app.key] != nil
        let hover = _hover.wrappedValue
        Menu {
            AppColorPicker(app: app, history: history)
        } label: {
            Circle().fill(color ?? .clear)
                .overlay { if color == nil && hover { Circle().strokeBorder(.secondary) } }
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Colour")
        .help("Choose the colour that shows \(app.name)")
        .overlay(alignment: .topTrailing) {
            if chosen && hover {
                Button("Remove Colour", systemImage: "xmark.circle.fill") { history.appColors[app.key] = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray)
                    .font(.system(size: 10))
                    .offset(x: 5, y: -5)
                    .help("Remove the colour and use the automatic one")
            }
        }
        // The hover area takes in the cross, which sits past the dot's corner.
        .padding(6)
        .contentShape(Rectangle())
        .onHover { _hover.wrappedValue = $0 }
        .padding(-6)
    }
}

/// The colours the user can choose for an app, and None (Automatic).
struct AppColorPicker: View {
    let app: AppKey
    let history: HistoryModel

    var body: some View {
        Picker("Colour", selection: Binding(get: { history.appColors[app.key] }, set: { history.appColors[app.key] = $0 })) {
            Text("None (Automatic)").tag(GroupColor?.none)
            Divider()
            ForEach(AppPalette.choices, id: \.self) { color in
                Label { Text(color.rawValue.capitalized) } icon: { Image(nsImage: GroupEditor.swatches[color]!) }.tag(Optional(color))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
