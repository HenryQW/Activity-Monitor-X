/// The toolbar search of the Disk and Disk Map screens: case- and diacritic-insensitive text in any of an item's names.
public enum NameSearch {
    /// The items with a name that holds `query`; an empty query keeps everything.
    public static func filter<Item>(_ items: [Item], query: String, names: (Item) -> [String]) -> [Item] {
        query.isEmpty ? items : items.filter { names($0).contains { $0.localizedStandardContains(query) } }
    }
}
