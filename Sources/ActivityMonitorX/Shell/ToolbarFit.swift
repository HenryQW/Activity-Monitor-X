import SwiftUI

/// What decides whether the Metric segments fit the toolbar row. Toolbar items cannot read the room they have, and
/// `ViewThatFits` does not work in them, so each part reports its real width here: the title pill, the item capsules and
/// the segments (laid out off screen first, as the pop-up hides the real ones; the drawn width replaces that once seen).
@Observable @MainActor
final class ToolbarFit {
    var pill: CGFloat = 0
    /// Calendar's Back button, between the Sidebar button and the pill; 0 on other screens.
    var back: CGFloat = 0
    /// The segments' ideal width, laid out off screen for the metrics now listed (`count` of them).
    var ideal: CGFloat = 0
    var count = 0
    /// The width the toolbar drew the segments at, by metric count: a little under the ideal one, and exact.
    var drawn: [Int: CGFloat] = [:]
    /// The trailing items by id, while they are in the toolbar.
    var items: [String: CGFloat] = [:]

    /// The search field that replaces the Search button: a system item that cannot report its width. It drew 266 to 325 pt
    /// in captures, so the room is kept for 300 pt.
    static let searchField: CGFloat = 300
    /// From the detail's leading edge to the title pill: the Sidebar button and its gaps, plus the 7 pt by which the
    /// segments' centre sits left of the detail's centre (measured).
    static let leading: CGFloat = 59
    /// The space Back adds besides its own width: none, it shares the Sidebar button's capsule (measured: with 8 pt
    /// Calendar asked for 16 pt too much and showed the pop-up where the segments fit).
    static let backGap: CGFloat = 0
    /// What the system adds to the item widths to reach the window edge: the trailing inset, and the space of each capsule.
    static let trailingInset: CGFloat = 10
    static let perItem: CGFloat = 4
    /// The least clear space between the segments and the pill or the first item capsule.
    static let gap: CGFloat = 8
    /// How much more room the segments need to come back once the pop-up shows: no flicker at the edge.
    static let hysteresis: CGFloat = 16

    var segments: CGFloat { drawn[count] ?? ideal }

    /// The detail width from which the segments fit. They are centred, so the longer side decides: the title pill, or
    /// the item capsules to the window edge (their trailing inset moves the centre 7 pt left).
    func need(searching: Bool) -> CGFloat {
        let widths = Array(items.values) + (searching ? [Self.searchField] : [])
        let trailing = widths.reduce(0, +) + Self.perItem * CGFloat(widths.count) + Self.trailingInset - 7
        return segments + 2 * (max(trailing, Self.leading + (back > 0 ? back + Self.backGap : 0) + pill) + Self.gap)
    }

    func compact(width: CGFloat, searching: Bool, was: Bool) -> Bool {
        ideal == 0 ? was : width < need(searching: searching) + (was ? Self.hysteresis : 0)
    }
}

extension View {
    /// Reports this item's width to `ToolbarFit` under `id`, and takes it back when the item leaves the toolbar.
    func fitItem(_ id: String, _ fit: ToolbarFit) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { if abs((fit.items[id] ?? 0) - $0) >= 1 { fit.items[id] = $0 } }
            .onDisappear { fit.items[id] = nil }
    }

    /// Reports Calendar's Back button width to `ToolbarFit`, and clears it when the button leaves the toolbar.
    func fitBack(_ fit: ToolbarFit) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { if abs(fit.back - $0) >= 1 { fit.back = $0 } }
            .onDisappear { fit.back = 0 }
    }
}
