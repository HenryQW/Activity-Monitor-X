import SwiftUI

/// Drawn parts, one design on every screen (SCR-19): Hardware, Disk and Energy draw a drive or a battery with these.

/// A drive as flash chips filled from the bottom to its used share, in the status colour; two chips for the startup
/// disk or volume, one for an external drive. No fill where the share is unknown.
struct FlashChips: View {
    let count: Int
    let share: Double?
    let color: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                let shape = RoundedRectangle(cornerRadius: 2)
                shape.fill(PartStyle.package)
                    .overlay(alignment: .bottom) {
                        if let share {
                            GeometryReader { proxy in
                                Rectangle().fill(color).frame(height: proxy.size.height * share).frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .clipShape(shape)
                    .overlay { if contrast == .increased { shape.strokeBorder(Color(nsColor: .separatorColor)) } }
                    .overlay(alignment: .topLeading) { Circle().fill(.tertiary).frame(width: 2.5, height: 2.5).offset(x: 2.5, y: 2.5) }
                    .frame(width: 13, height: 20)
            }
        }
    }
}

/// A battery filled from the left to its charge in the status colour (`level`: 1 low, 2 critical), with a bolt while it
/// charges.
struct BatteryShape: View {
    let percent: Double?
    let charging: Bool
    let level: Int
    @Environment(\.colorSchemeContrast) private var contrast

    /// 2 at 10 % or less, 1 at 20 % or less, while not charging.
    static func level(percent: Int?, charging: Bool) -> Int {
        guard let percent, !charging else { return 0 }
        return percent <= 10 ? 2 : percent <= 20 ? 1 : 0
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        let trace = PartStyle.trace(contrast)
        HStack(spacing: 1) {
            shape.fill(PartStyle.package)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 1.5).fill(ChipDiagram.status(level))
                            .frame(width: max(0, proxy.size.width - 4) * min(percent ?? 0, 100) / 100)
                            .frame(maxHeight: .infinity)
                            .padding(2)
                    }
                }
                .overlay { shape.strokeBorder(trace, lineWidth: 1.2) }
                .overlay { if charging { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.primary) } }
                .frame(width: 26, height: 12)
            RoundedRectangle(cornerRadius: 0.5).fill(trace).frame(width: 2, height: 5)
        }
    }
}

extension View {
    /// The cell around a drawn part or a fact (Hardware, Disk, Calendar): the layout's padding, the quinary fill with 7 pt
    /// corners and the accent outline while it is selected.
    func partCell(selected: Bool = false, padding: CGFloat = Layout.padding) -> some View {
        self.padding(padding)
            .background(.quinary, in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.tint, lineWidth: 2).opacity(selected ? 1 : 0) }
    }
}

enum PartStyle {
    /// The fill of a part's empty body.
    static let package = Color(nsColor: .secondarySystemFill)

    /// Outlines and stands: stronger with Increase Contrast.
    static func trace(_ contrast: ColorSchemeContrast) -> Color {
        Color(nsColor: contrast == .increased ? .secondaryLabelColor : .tertiaryLabelColor)
    }
}
