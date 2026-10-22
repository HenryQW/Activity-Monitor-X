import AMXCore
import SwiftUI

/// The app's chosen colour as a split button: the swatch (empty for automatic) applies the last chosen colour, the
/// arrow opens the colours and None.
struct AppColorMenu: View {
    let app: AppKey
    let history: HistoryModel

    var body: some View {
        Menu {
            AppColorPicker(app: app, history: history)
        } label: {
            if let color = history.appColors[app.key] {
                Image(nsImage: GroupEditor.swatches[color]!)
            } else {
                Image(systemName: "circle")
            }
        } primaryAction: {
            history.appColors[app.key] = history.lastAppColor
        }
        .fixedSize()
        .accessibilityLabel("Colour")
        .help("Choose the app's colour")
    }
}

/// The colours the user can choose for an app, and None (Automatic); a choice is also the button's next colour.
struct AppColorPicker: View {
    let app: AppKey
    let history: HistoryModel

    var body: some View {
        Picker("Colour", selection: Binding(get: { history.appColors[app.key] }, set: { color in
            history.appColors[app.key] = color
            if let color { history.lastAppColor = color }
        })) {
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
