import AMXCore
import Foundation

enum SidebarItem: Hashable {
    case apps
    case calendar
    case alerts
    case pinned(AppKey)
    case group(UUID)
    case disk
    case diskMap
    case hardware
    case energy

    /// The System section and Calendar: these screens show no app rows, so search, Hide Quiet and the inspector do not
    /// apply, nor Metric outside Calendar.
    var isSystem: Bool {
        switch self {
        case .calendar, .disk, .diskMap, .hardware, .energy: true
        default: false
        }
    }
}
