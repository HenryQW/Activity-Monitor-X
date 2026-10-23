import AMXCore
import Foundation

extension CalendarPeriod {
    /// Day and Hour select a line (a bar) of a cell, not the cell.
    var selectsBars: Bool { self == .day || self == .hour }
}

extension CalendarModel {
    /// The span [start, end) of the selected bars; nil outside Day and Hour or with none selected.
    var selectedBars: (start: Double, end: Double)? {
        guard let selected, let page, page.period.selectsBars else { return nil }
        return (selected.lowerBound, selected.upperBound + page.bucket)
    }

    /// The arrow keys: moves the selection by `steps` bars that have data, or with `extend` stretches it there. With no
    /// selection the first or the last bar is selected.
    func moveBar(_ steps: Int, extend: Bool) {
        guard let page, page.period.selectsBars else { return }
        let starts = page.cells.flatMap { cell in cell.lines.indices.filter { cell.lines[$0] != nil }.map(cell.lineStart) }
        guard !starts.isEmpty else { return }
        let edge = steps > 0 ? selected?.upperBound : selected?.lowerBound
        let current = edge.flatMap { edge in starts.lastIndex { $0 <= edge } }
        let target = current.map { min(max($0 + steps, 0), starts.count - 1) } ?? (steps > 0 ? 0 : starts.count - 1)
        select(starts[target], starts[target], extending: extend ? selected : nil)
    }
}
