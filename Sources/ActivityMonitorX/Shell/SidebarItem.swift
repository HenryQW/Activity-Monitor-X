import AMXCore
import Foundation

enum SidebarItem: Hashable {
    case apps
    case calendar
    case alerts
    case pinned(AppKey)
    case group(UUID)
    case disk
    case hardware
    case energy

    /// The System section and Calendar: these screens show no app rows, so Hide Quiet does not apply, nor Metric outside
    /// Calendar. Search and the inspector apply on every screen, to what it lists.
    var isSystem: Bool {
        switch self {
        case .calendar, .disk, .hardware, .energy: true
        default: false
        }
    }

    /// The screen's search finds apps; Disk and Hardware search their own items.
    var searchesApps: Bool {
        switch self {
        case .disk, .hardware: false
        default: true
        }
    }

    /// What the toolbar search finds on the screen; Disk's Space pill finds files (`Selection.searchPrompt`).
    var searchPrompt: String {
        switch self {
        case .apps, .pinned, .group: "App, process or PID"
        case .alerts: "App or message"
        case .calendar, .energy: "App"
        case .disk: "Volume or disk"
        case .hardware: "Hardware"
        }
    }
}
