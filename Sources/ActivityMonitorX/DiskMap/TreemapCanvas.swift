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
    let path: ([Int]) -> String?

    var body: some View {
        GeometryReader { geometry in
            let cells = Treemap.cells(node, in: CGRect(origin: .zero, size: geometry.size))
            let kinds = Self.kinds(cells, node: node, baseNames: baseNames)
            Canvas { context, _ in Self.draw(cells, kinds: kinds, in: &context) }
                // Hover lives in its own view, so a pointer move does not lay out or redraw the cells.
                .overlay { Hover(cells: cells, base: base, selected: selected, open: open, path: path) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// Cells come parent first, so a stack of names gives each cell its folders. A folder's largest items come first
    /// among its children (size descending).
    private static func kinds(_ cells: [Treemap.Cell], node: DiskTree.Node, baseNames: [String]) -> [FileKind] {
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

    private static func draw(_ cells: [Treemap.Cell], kinds: [FileKind], in context: inout GraphicsContext) {
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
            if !inner, rect.width >= 60, rect.height >= 20 {
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
    let base: [Int]
    let selected: [Int]?
    let open: ([Int]) -> Void
    let path: ([Int]) -> String?
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
                if let hovered {
                    Text("\(hovered.name) · \(Metric.bytes(Double(hovered.size)))")
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.background, in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
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
            if let item = _menuItem.wrappedValue { DiskItemMenu(path: path(item)) }
        }
    }

    /// The deepest cell at the point: children come after their folder.
    private func cell(at point: CGPoint) -> Treemap.Cell? { cells.last { $0.rect.contains(point) } }
}
