/// One row of the Hardware inventory table: a node with its properties, then its child nodes, as children.
public struct HardwareRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let value: String
    public let children: [HardwareRow]?

    public init(id: String, name: String, value: String, children: [HardwareRow]?) {
        (self.id, self.name, self.value, self.children) = (id, name, value, children)
    }

    /// The toolbar search: a row whose name, or value when it has no children (a parent's value is its count), holds
    /// `query` stays with all its rows. A row that only holds such a row stays with the children that lead to one, and is
    /// in `opened`, so the match shows. An empty query keeps everything.
    public static func filter(_ rows: [HardwareRow], query: String) -> (rows: [HardwareRow], opened: Set<String>) {
        guard !query.isEmpty else { return (rows, []) }
        var opened: Set<String> = []
        func keep(_ rows: [HardwareRow]) -> [HardwareRow] {
            rows.compactMap { row in
                if row.name.localizedStandardContains(query) || row.children == nil && row.value.localizedStandardContains(query) {
                    return row
                }
                let children = keep(row.children ?? [])
                guard !children.isEmpty else { return nil }
                opened.insert(row.id)
                return HardwareRow(id: row.id, name: row.name, value: row.value, children: children)
            }
        }
        return (keep(rows), opened)
    }

    /// The rows from the section down to the row with `id`; empty when no row has it.
    public static func path(to id: String, in rows: [HardwareRow]) -> [HardwareRow] {
        for row in rows {
            if row.id == id { return [row] }
            let below = path(to: id, in: row.children ?? [])
            if !below.isEmpty { return [row] + below }
        }
        return []
    }
}
