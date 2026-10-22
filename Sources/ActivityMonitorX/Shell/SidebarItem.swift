import AMXCore
import Foundation

enum SidebarItem: Hashable {
    case apps
    case alerts
    case pinned(AppKey)
    case group(UUID)
    case disk
    case diskMap
    case hardware

    /// The System section: these screens show no app data, so Metric, Hide Quiet and the inspector do not apply.
    var isSystem: Bool {
        switch self {
        case .disk, .diskMap, .hardware: true
        default: false
        }
    }
}
