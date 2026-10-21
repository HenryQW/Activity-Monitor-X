import AMXCore
import Foundation

enum SidebarItem: Hashable {
    case timeline
    case apps
    case pinned(AppKey)
    case group(UUID)
}
