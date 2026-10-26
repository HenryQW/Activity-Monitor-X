import SwiftUI

/// The floating layout's spacings, from 8, 12 and 16 pt only. Level 1 is the window chrome (toolbar row, sidebar and
/// inspector panels), level 2 the content controls that float inside the content column (range bar, span capsule,
/// footer, Calendar bar, Space capsules), level 3 the data under both (chart, table, grid, treemap), never glass.
enum Layout {
    /// Insets of panels and floating controls from their container, and the gaps between them.
    static let inset: CGFloat = 8
    /// Padding inside a capsule.
    static let padding: CGFloat = 12
    /// Panel corners (concentric to the window's).
    static let corner: CGFloat = 16
    /// The height of the toolbar row and of the level 2 bars.
    static let bar: CGFloat = 40
}

extension View {
    /// A level 2 control: its own glass capsule of the bar's height, so it floats over the data. Regular glass: with
    /// `.clear` the table rows under the footer showed through its figures and could not be read; the glass has no shadow
    /// setting.
    func floatingCapsule(padding: CGFloat = Layout.inset) -> some View {
        self.padding(.horizontal, padding)
            .frame(height: Layout.bar)
            .glassEffect(.regular, in: .capsule)
    }

    /// A level 2 bar that spans the content column (the metric footer).
    func floatingBar() -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: Layout.corner))
    }

    /// A level 1 panel (the inspector): the same glass as the system sidebar, in a 16 pt corner.
    func floatingPanel() -> some View {
        clipShape(.rect(cornerRadius: Layout.corner))
            .glassEffect(.regular, in: .rect(cornerRadius: Layout.corner))
    }
}

/// A choice of a few values in a level 2 capsule, as the toolbar shows its segments: the chosen value is a pill on the
/// capsule's glass and there is no track. A segmented picker draws its own track in every style (glass in glass), so the
/// values are toggles in the accessory bar style; the group reads as one control with the title.
struct CapsuleChoice<Value: Hashable, Label: View>: View {
    let title: String
    let values: [Value]
    let selection: Binding<Value?>
    @ViewBuilder let label: (Value) -> Label

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Toggle(isOn: Binding(get: { selection.wrappedValue == value }, set: { if $0 { selection.wrappedValue = value } })) {
                    label(value)
                }
                .toggleStyle(.button)
            }
        }
        .buttonStyle(.accessoryBar)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
