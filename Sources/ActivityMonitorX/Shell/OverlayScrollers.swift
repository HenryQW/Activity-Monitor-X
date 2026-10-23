import AppKit
import SwiftUI

extension View {
    /// Thin overlay scroll bars on the scroll view this view sits in, whatever the system "Show scroll bars" setting (the
    /// inspector panel only; other views keep the system style, BLD-2). Apply it to one row of each inspector `Form` or `List`.
    func overlayScrollers() -> some View { background(OverlayScrollers()) }
}

/// SwiftUI has no API for the scroller style, so this sets `scrollerStyle` on the AppKit scroll view that holds it. It lives
/// inside the scrolling content, so it is made again with the scroll view and sets the style each time. The system resets
/// the style when the setting changes, so that sets it again too.
private struct OverlayScrollers: NSViewRepresentable {
    final class Anchor: NSView {
        var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() { enclosingScrollView?.scrollerStyle = .overlay }
    }

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.observer = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak view] _ in
            // After the scroll view takes the new system style.
            DispatchQueue.main.async { view?.enclosingScrollView?.scrollerStyle = .overlay }
        }
        return view
    }

    func updateNSView(_ view: Anchor, context: Context) {}

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.observer.map(NotificationCenter.default.removeObserver)
    }
}
