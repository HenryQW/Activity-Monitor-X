import SwiftUI

/// The floating layout's spacings, from 4, 8, 12 and 16 pt only. Level 1 is the window chrome (toolbar row, sidebar and
/// inspector panels), level 2 the content controls that float inside the content column (range bar, span capsule,
/// footer, Calendar bar, Space capsules), level 3 the data under both (chart, table, grid, treemap), never glass.
enum Layout {
    /// The gap inside one row or one block: an icon and its label, a value over its label, a symbol and its count.
    static let gap: CGFloat = 4
    /// Insets of panels and floating controls from their container, the gaps between them and between cells, and the
    /// padding inside a small tile (Calendar's glyph cells).
    static let inset: CGFloat = 8
    /// Padding inside a capsule, a card, a panel or a cell: no text is nearer the edge than this.
    static let padding: CGFloat = 12
    /// Panel and card corners (concentric to the window's).
    static let corner: CGFloat = 16
    /// The gap between the sections of a page (Disk's charts, disks, volumes and containers).
    static let section: CGFloat = 16
    /// The height of the toolbar row and of the level 2 bars.
    static let bar: CGFloat = 40
}

extension View {
    /// A level 2 control: its own glass capsule of the bar's height, so it floats over the data. Regular glass: with
    /// `.clear` the table rows under the footer showed through its figures and could not be read; the glass has no shadow
    /// setting.
    func floatingCapsule(padding: CGFloat = Layout.padding) -> some View {
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
        HStack(spacing: Layout.gap) {
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

/// A figure in a footer strip (Apps, Energy): the value over its label, no box.
struct Figure<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.gap) {
            value.font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        // No fixed size: in a strip's narrowest form the words truncate rather than leave the capsule.
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
