import SwiftUI

/// An inspector section that opens and closes (IN1): its first row names it and gives its summary at the right, so a
/// closed card still says what matters. Open or closed is kept per title, for every inspector that shows the card.
struct CardSection<Content: View>: View {
    let title: String
    let summary: Text?
    @ViewBuilder let content: Content
    private let _open: AppStorage<Bool>

    init(_ title: String, summary: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content()
        _open = AppStorage(wrappedValue: true, "inspectorCard." + title)
    }

    var body: some View {
        let open = _open.wrappedValue
        // The title row is the card's first row, so a closed card is still a card: an empty section shows its header
        // smaller and out of place.
        Section {
            Button {
                withAnimation(Motion.smooth(0.2)) { _open.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(title).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    summary?.foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the \(title) rows" : "Show the \(title) rows")
            .accessibilityLabel(title)
            .accessibilityValue(open ? "Open" : "Closed")
            .accessibilityHint(open ? "Hides the rows" : "Shows the rows")
            if open { content }
        }
    }
}
