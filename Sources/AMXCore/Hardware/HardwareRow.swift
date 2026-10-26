/// One row of the Hardware inventory table: a node with its properties, then its child nodes, as children.
public struct HardwareRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let value: String
    public let children: [HardwareRow]?
    /// The node's symbol; nil for a property row.
    public let symbol: String?

    public init(id: String, name: String, value: String, children: [HardwareRow]?, symbol: String? = nil) {
        (self.id, self.name, self.value, self.children, self.symbol) = (id, name, value, children, symbol)
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

    /// Each row with the property `key` (and `value`, where given) among its children, with that property's row, in tree
    /// order. A property row's id is its node's row id, "=" and the key.
    public static func rows(holding key: String, value: String? = nil, in rows: [HardwareRow]) -> [(row: HardwareRow, property: HardwareRow)] {
        rows.flatMap { row -> [(row: HardwareRow, property: HardwareRow)] in
            let children = row.children ?? []
            let property = children.first { $0.children == nil && $0.id.hasSuffix("=" + key) && (value == nil || $0.value == value) }
            return (property.map { [(row, $0)] } ?? []) + Self.rows(holding: key, value: value, in: children)
        }
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
