import SwiftUI

/// An inspector section that opens and closes (IN1): its first row names it and gives its summary at the right, so a
/// closed card still says what matters. Open or closed is kept per title, for every inspector that shows the card.
struct CardSection<Content: View>: View {
    let title: String
    let summary: AnyView?
    /// The summary as VoiceOver says it, with the card's state.
    let spoken: String?
    /// A hint under the card, as a section footer.
    var footer: Text?
    @ViewBuilder let content: Content
    private let _open: AppStorage<Bool>

    init(_ title: String, summary: Text? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, summary: summary.map { AnyView($0) }, spoken: nil, content: content)
        self.footer = footer
    }

    /// A summary that is more than text: a number that rolls (INS-9); `spoken` says it to VoiceOver.
    init(_ title: String, summary: AnyView?, spoken: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.spoken = spoken
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
                // The chevron is a control, not part of the title: it keeps the 8 pt that separates items.
                HStack(spacing: Layout.inset) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(title).fontWeight(.semibold)
                    Spacer(minLength: Layout.inset)
                    summary?.foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the \(title) rows" : "Show the \(title) rows")
            .accessibilityLabel(title)
            .accessibilityValue([spoken, open ? "Open" : "Closed"].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(open ? "Hides the rows" : "Shows the rows")
            if open { content }
        } footer: {
            footer
        }
    }
}

/// A selection's name as the inspector's first row (INS-4).
struct InspectorTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Section { Text(text).font(.title3.bold()).overlayScrollers() }
    }
}
