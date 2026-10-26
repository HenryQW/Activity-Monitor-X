# Native components with default styling

Popovers, menu bar content, tiles and settings use native SwiftUI or AppKit components with their default look: no custom glass, fonts, backgrounds or corner radii. Event markers show the same native popover on hover and on click. The menu bar item is a `MenuBarExtra` (`.window` style) with a template-image sparkline, not an `NSStatusItem` with drawn widgets. The user prefers consistency with macOS over custom polish; the exception is the chart value bubble, which follows the pointer and stays custom unless a native popover can track it without flicker. Decisions D24, D25.

Superseded in part: every popover and hover preview is Liquid Glass (D65); the menu bar item is an `NSStatusItem` with a real system menu, gauges in its first item (D69).
