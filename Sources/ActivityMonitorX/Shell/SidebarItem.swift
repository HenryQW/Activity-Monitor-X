import AMXCore
import Foundation

enum SidebarItem: Hashable {
    case timeline
    case apps
    case alerts
    case pinned(AppKey)
    case group(UUID)
}
