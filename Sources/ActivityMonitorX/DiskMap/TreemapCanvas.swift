import AMXCore
import SwiftUI

/// The focused folder as a squarified treemap, three levels deep. Neutral fills darken with depth; colour carries no
/// meaning here, so only the hovered or selected item has an accent stroke. The table beside it is the accessible path.
struct TreemapCanvas: View {
    let node: DiskTree.Node
    /// The focused folder's index path; a cell's own path is relative to it.
    let base: [Int]
    /// The table's selection, an index path in the tree.
    let selected: [Int]?
    let label: String
    let open: ([Int]) -> Void
    let path: ([Int]) -> String?

    var body: some View {
        GeometryReader { geometry in
            let cells = Treemap.cells(node, in: CGRect(origin: .zero, size: geometry.size))
            Canvas { context, _ in Self.draw(cells, in: &context) }
                // Hover lives in its own view, so a pointer move does not lay out or redraw the cells.
                .overlay { Hover(cells: cells, base: base, selected: selected, open: open, path: path) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private static func draw(_ cells: [Treemap.Cell], in context: inout GraphicsContext) {
        for (i, cell) in cells.enumerated() {
            let rect = cell.rect.insetBy(dx: 0.5, dy: 0.5)
            // Children draw over their folder, so each level is a shade darker.
            context.fill(Path(rect), with: .color(.primary.opacity(cell.kind == .folder || cell.kind == .file ? 0.08 : 0.04)))
            // Only cells with nothing drawn inside get a label, so labels never overlap. Cells come parent first.
            let inner = i + 1 < cells.count && cells[i + 1].path.count > cell.path.count
            if !inner, rect.width >= 60, rect.height >= 20 {
                context.draw(Text(cell.name).font(.caption).foregroundStyle(.secondary), in: rect.insetBy(dx: 4, dy: 3))
            }
        }
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
        GeometryReader { geometry in
            ZStack(alignment: (_location.wrappedValue?.y ?? 0) > geometry.size.height * 0.66 ? .topLeading : .bottomLeading) {
                Color.clear.contentShape(.rect)
                if let highlight {
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
