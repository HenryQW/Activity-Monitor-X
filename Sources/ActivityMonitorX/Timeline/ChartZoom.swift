import AMXCore
import SwiftUI

/// The level 2 zoom pill on a chart's trailing edge: Zoom In above Zoom Out, one capsule. A button that cannot act is
/// disabled, so the pill never changes size. Glass on the content layer by the user's choice, against ADR 0009.
struct ChartZoom: View {
    /// Room that a chart keeps free at its trailing edge, so nothing of the chart sits under the pill.
    static let width: CGFloat = 32 + Layout.inset
    @Environment(HistoryModel.self) private var history

    var body: some View {
        VStack(spacing: 0) {
            button("Zoom In", "plus.magnifyingglass", hint: zoomInHint, enabled: history.canZoomIn, action: history.zoomIn)
            Divider().padding(.horizontal, 6)
            button("Zoom Out", "minus.magnifyingglass", hint: zoomOutHint, enabled: history.widerRange != nil, action: history.zoomOut)
        }
        .frame(width: 32)
        .glassEffect(.regular, in: .capsule)
    }

    private func button(_ title: String, _ symbol: String, hint: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 32, height: 32).contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .help(hint)
    }

    private var centre: String {
        let window = history.window
        return Date(timeIntervalSince1970: (window.lowerBound + window.upperBound) / 2).formatted(.dateTime.day().month(.abbreviated))
    }

    private var zoomInHint: String {
        if history.range == .live { return "Zoom is not available in Live" }
        if let span = history.span {
            let format = history.range.timeFormat
            let (from, to) = (Date(timeIntervalSince1970: span.lowerBound), Date(timeIntervalSince1970: span.upperBound))
            return "Zoom in to \(from.formatted(format)) to \(to.formatted(format))"
        }
        guard let narrower = history.narrowerRange else { return "Already at the narrowest range, 1 hour" }
        return "Zoom in to \(narrower.spoken) around \(centre)"
    }

    private var zoomOutHint: String {
        if history.range == .live { return "Zoom is not available in Live" }
        guard let wider = history.widerRange else { return "Already at the widest range, 90 days" }
        return history.zoomsOutToRange() ? "Zoom out to the last \(wider.spoken)" : "Zoom out to \(wider.spoken) around \(centre)"
    }
}
