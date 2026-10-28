import AMXCore
import SwiftUI

/// The focused folder as a squarified treemap, three levels deep. Fills are the file kind's colour at about 35 %, so the
/// labels stay primary text; no red, yellow or orange (warning, critical and app colours). The hovered or selected item
/// and its folders have an accent stroke, and the rest dims. The table beside it is the accessible path.
struct TreemapCanvas: View {
    let node: DiskTree.Node
    /// The focused folder's index path; a cell's own path is relative to it.
    let base: [Int]
    /// The names from the scanned root's first level to the focused folder, for the cells' kinds.
    let baseNames: [String]
    /// The table's selection, an index path in the tree.
    let selected: [Int]?
    let label: String
    let open: ([Int]) -> Void

    var body: some View {
        GeometryReader { geometry in
            let cells = Treemap.cells(node, in: CGRect(origin: .zero, size: geometry.size))
            let kinds = Self.kinds(cells, node: node, baseNames: baseNames)
            Canvas { context, _ in Self.draw(cells, kinds: kinds, in: &context) }
                // Hover lives in its own view, so a pointer move does not lay out or redraw the cells.
                .overlay { Hover(cells: cells, total: node.size, base: base, selected: selected, open: open) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// Cells come parent first, so a stack of names gives each cell its folders. A folder's largest items come first
    /// among its children (size descending).
    static func kinds(_ cells: [Treemap.Cell], node: DiskTree.Node, baseNames: [String]) -> [FileKind] {
        var names: [String] = []
        return cells.map { cell in
            names = Array(names.prefix(cell.depth - 1)) + [cell.name]
            var item = cell.path.reduce(node) { $0.children[$1] }, largest: [String] = []
            while let first = item.children.first {
                largest.append(first.name)
                item = first
            }
            return FileKind.of(baseNames + names, largest: largest)
        }
    }

    static func draw(_ cells: [Treemap.Cell], kinds: [FileKind], labels: Bool = true, in context: inout GraphicsContext) {
        for (i, cell) in cells.enumerated() {
            let rect = cell.rect.insetBy(dx: 0.5, dy: 0.5)
            // Only cells with nothing drawn inside get a label, so labels never overlap.
            let inner = i + 1 < cells.count && cells[i + 1].path.count > cell.path.count
            let color = kinds[i].color
            switch cell.kind {
            // A folder with cells inside shows as a faint frame around them.
            case .folder where inner: context.fill(Path(rect), with: .color(color.opacity(0.12)))
            case .folder, .file:
                context.fill(Path(rect), with: .color(color.opacity(0.35)))
                context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(color.opacity(0.6)), lineWidth: 1)
            case .smaller: context.fill(Path(rect), with: .color(color.opacity(0.18)))
            case .refused: context.fill(Path(rect), with: .color(.primary.opacity(0.04)))
            }
            if labels, !inner, rect.width >= 60, rect.height >= 20 {
                context.draw(Text(cell.name).font(.caption).foregroundStyle(.primary), in: rect.insetBy(dx: 4, dy: 3))
            }
        }
    }
}

extension FileKind {
    var label: String {
        switch self {
        case .applications: "Applications"
        case .documents: "Documents"
        case .media: "Media"
        case .developer: "Developer"
        case .system: "System"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .applications: .blue
        case .documents: .teal
        case .media: .purple
        case .developer: .indigo
        case .system: .gray
        case .other: .brown
        }
    }
}

/// The treemap's colours under it, with the round dot of the app list.
struct FileKindLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(FileKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                    Text(kind.label).lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Colours by file kind")
    }
}

private struct Hover: View {
    let cells: [Treemap.Cell]
    /// The focused folder's size, the share's whole for a top level cell.
    let total: UInt64
    let base: [Int]
    let selected: [Int]?
    let open: ([Int]) -> Void
    private let _location = State<CGPoint?>(initialValue: nil)
    /// The last item under the pointer, kept after the pointer leaves for the context menu.
    private let _menuItem = State<[Int]?>(initialValue: nil)

    var body: some View {
        let hovered = _location.wrappedValue.flatMap(cell(at:))
        let highlight = hovered ?? selected.flatMap { s in
            s.starts(with: base) ? cells.first { $0.path == Array(s.dropFirst(base.count)) } : nil
        }
        // The highlighted item's folders, outermost first.
        let folders = highlight.map { h in cells.filter { $0.path.count < h.path.count && h.path.starts(with: $0.path) } } ?? []
        GeometryReader { geometry in
            ZStack(alignment: (_location.wrappedValue?.y ?? 0) > geometry.size.height * 0.66 ? .topLeading : .bottomLeading) {
                Color.clear.contentShape(.rect)
                if let highlight {
                    // The rest dims, so the item's top folder stands out.
                    Path { dim in
                        dim.addRect(CGRect(origin: .zero, size: geometry.size))
                        dim.addRect((folders.first ?? highlight).rect)
                    }
                    .fill(.background.opacity(0.45), style: FillStyle(eoFill: true))
                    ForEach(folders, id: \.path) { Path($0.rect.insetBy(dx: 1, dy: 1)).stroke(.tint, lineWidth: 1) }
                    Path(highlight.rect.insetBy(dx: 1, dy: 1)).stroke(.tint, lineWidth: 2)
                }
                if let hovered { card(hovered).padding(8) }
            }
        }
        // The treemap itself is not read item by item; the item under the pointer is its value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Item under the pointer")
        .accessibilityValue(hovered.map { card($0).summary } ?? "None")
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                _location.wrappedValue = point
                // Absolute, so a click that changes the focus cannot point the menu at another item.
                _menuItem.wrappedValue = cell(at: point).map { base + $0.path }
            case .ended:
                _location.wrappedValue = nil
            }
        }
        // A click focuses the folder under the pointer, or the folder of the file under it.
        .onTapGesture { point in
            guard let cell = cell(at: point) else { return }
            let folder = cell.kind == .folder ? cell.path : Array(cell.path.dropLast())
            if !folder.isEmpty { open(base + folder) }
        }
        .contextMenu {
            if let item = _menuItem.wrappedValue { DiskItemMenu(id: item) }
        }
    }

    /// Name and size on top; the kind and the share of the folder it is in.
    private func card(_ cell: Treemap.Cell) -> PreviewCard<EmptyView> {
        let parent = cells.first { $0.path == Array(cell.path.dropLast()) }?.size ?? total
        let kind = switch cell.kind {
        case .folder: "Folder"
        case .file: "File"
        case .smaller: "Smaller items"
        case .refused: "No access"
        }
        return PreviewCard(size: .compact, title: cell.name, top: Metric.bytes(Double(cell.size)),
                           sections: [.init(rows: [.init(label: "Kind", value: kind),
                                                   .init(label: "Share of its folder",
                                                         value: (parent > 0 ? Double(cell.size) / Double(parent) : 0).formatted(.percent.precision(.fractionLength(0))))])])
    }

    /// The deepest cell at the point: children come after their folder.
    private func cell(at point: CGPoint) -> Treemap.Cell? { cells.last { $0.rect.contains(point) } }
}
