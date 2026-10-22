# The inspector is a pane inside the content area, not SwiftUI `.inspector`

The user requires that opening the inspector never resizes the window. SwiftUI's `.inspector` grows any window narrower than the closed minimum plus twice the inspector width (measured 1,320 pt), whatever minimum the app sets. So the inspector is a trailing pane inside the detail area with its own draggable, accessible divider and remembered width; the content shrinks instead. Do not switch back to `.inspector`. Decisions D21, D23.
