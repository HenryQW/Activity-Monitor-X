import AppKit

/// Widens the window when the toolbar would not fit, so no item goes into » and the split view never collapses the
/// sidebar to make room: opening the inspector grows a narrow window by the inspector's width, and a
/// group's Score segment grows it to the width that segment needs. The window stays on its screen.
@MainActor
enum WindowFit {
    /// Window widths at which the toolbar shows every item, sidebar shown (measured): 1020 pt without the inspector,
    /// between 1320 and 1360 pt with it. The 7th segment (Score) fits from 1050 pt at any title length (the title
    /// truncates); 40 pt more keeps a margin.
    private static func toolbarWidth(inspector: Bool, score: Bool) -> CGFloat {
        (inspector ? 1360 : 1020) + (score ? 40 : 0)
    }

    /// The inspector's ideal width in `MainWindow`.
    private static let inspectorWidth: CGFloat = 280

    /// Grows the window before the inspector opens: once the inspector is in, the split view has already made room.
    static func toggleInspector(_ selection: Selection, score: Bool) {
        if !selection.inspectorShown, let window, window.frame.width < toolbarWidth(inspector: true, score: score) {
            grow(window, to: max(window.frame.width + inspectorWidth, toolbarWidth(inspector: true, score: score)))
        }
        selection.inspectorShown.toggle()
    }

    /// For a group's toolbar, which adds the Score segment.
    static func fitScore(inspector: Bool) {
        if let window { grow(window, to: toolbarWidth(inspector: inspector, score: true)) }
    }

    /// The main window, not minimized, hidden, fully covered, or on a locked screen. The menu bar panel and Settings
    /// do not count.
    static var windowShown: Bool {
        window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
    }

    /// `Window(id: "main")` names its window "main" (measured).
    static var window: NSWindow? { NSApp.windows.first { $0.identifier?.rawValue == "main" } }

    private static func grow(_ window: NSWindow, to width: CGFloat) {
        guard window.frame.width < width, !window.styleMask.contains(.fullScreen),
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(width, screen.width)
        // Grow to the right, or to the left where the right edge would leave the screen.
        frame.origin.x = max(min(frame.origin.x, screen.maxX - frame.width), screen.minX)
        // Animated; the call returns when the window has its new size, before the inspector opens.
        window.setFrame(frame, display: true, animate: true)
    }
}
