import AMXCore

enum SidebarItem: Hashable {
    case timeline
    case apps
    case pinned(AppKey)
}
