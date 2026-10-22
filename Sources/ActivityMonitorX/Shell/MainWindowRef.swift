import AppKit

/// The main window, as AppKit sees it. The window never resizes itself: the inspector is a pane inside the content
/// area (`InspectorPane`), so opening it shrinks the content, not the window.
@MainActor
enum MainWindowRef {
    /// The main window, not minimized, hidden, fully covered, or on a locked screen. The menu bar panel and Settings
    /// do not count.
    static var windowShown: Bool {
        window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
    }

    /// `Window(id: "main")` names its window "main" (measured).
    static var window: NSWindow? { NSApp.windows.first { $0.identifier?.rawValue == "main" } }
}
