/// The saved order of one sidebar section, merged with the items the app has now.
public enum SidebarOrder {
    /// Saved ids that still exist, in saved order, without duplicates; new default ids go at the end in default order.
    public static func merge(saved: [String], defaults: [String]) -> [String] {
        var seen = Set<String>()
        let kept = saved.filter { defaults.contains($0) && seen.insert($0).inserted }
        return kept + defaults.filter { !seen.contains($0) }
    }
}
