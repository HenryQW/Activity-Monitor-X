import AMXCore
import SwiftUI

/// The Calendar's cells: gapless with hairline separators, square, each with its value, lines and busiest app. A click
/// selects a cell, a drag selects a span drawn as one outline, a double-click opens the finer period. The pointer on a cell
/// shows its preview beside it. In Day and Hour the unit is the bar (a line of a cell), not the cell: the pointer marks a
/// bar, a click selects it, a drag selects a span of bars, and no cell outline is drawn.
struct CalendarGrid: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @Environment(Preferences.self) private var preferences
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme
    let page: CalendarPage
    let footer: CalendarFooter
    /// Told the width the cells take, so the Month tiles above line up with them.
    var onWidth: (CGFloat) -> Void = { _ in }

    /// What the pointer is on: a cell, or the week cell at the end of a row.
    private struct Hit: Equatable {
        let row: Int
        let column: Int
        /// The starts of the first and the last cell it covers.
        let low: Double
        let high: Double
        let cell: CalendarCell
        /// The line under the pointer in Day and Hour.
        var bar: Int?
        var hasData: Bool { bar.map { cell.lines[$0] != nil } ?? (cell.value != nil) }
    }

    private struct Layout {
        let rows: Int
        let columns: Int
        /// A cell at the end of each row: the week.
        let rowColumn: Bool
        let gutter: CGFloat
        let header: CGFloat
        let cell: CGSize
        let origin: CGFloat
        /// The pane the grid sits in: a preview stays inside it.
        let pane: CGSize

        var width: CGFloat { cell.width * CGFloat(columns + (rowColumn ? 1 : 0)) }
        var height: CGFloat { cell.height * CGFloat(rows) }
    }

    private let _hover = State<Hit?>(initialValue: nil)
    private let _pointer = State<CGPoint>(initialValue: .zero)
    /// Where the input layer starts in the Calendar's content, for the place a zoom grows from.
    private let _inputOrigin = State<CGPoint>(initialValue: .zero)
    /// Where a drag began: the span it selects runs from there.
    private let _anchor = State<Hit?>(initialValue: nil)
    private let _dragging = State(initialValue: false)
    /// The selection a shift-drag extends.
    private let _base = State<ClosedRange<Double>?>(initialValue: nil)

    private var calendar: Calendar { page.calendar }
    private var extras: [TimeZone] { preferences.extraZoneIDs.compactMap(TimeZone.init(identifier:)).filter { $0 != calendar.timeZone } }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            let colors = AppPalette.colors(for: page.apps, chosen: history.appColors)
            HStack(alignment: .top, spacing: 0) {
                if layout.gutter > 0 { gutter(layout) }
                VStack(alignment: .leading, spacing: 0) {
                    if layout.header > 0 { header(layout) }
                    cells(layout, colors: colors)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { onWidth($0) }
            .padding(.leading, layout.origin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding([.horizontal, .bottom])
        .accessibilityElement(children: .contain)
    }

    // MARK: Layout

    private func layout(in size: CGSize) -> Layout {
        let rows = page.grid.count, columns = page.grid[0].count
        let rowColumn = page.period == .month || page.period == .week
        let gutter: CGFloat = page.period == .week ? 80 : 0
        let header: CGFloat = rowColumn ? 24 : 0
        if page.period == .hour { return Layout(rows: 1, columns: 1, rowColumn: false, gutter: 0, header: 0, cell: CGSize(width: size.width, height: min(size.height, 320)), origin: 0, pane: size) }
        let across = CGFloat(columns + (rowColumn ? 1 : 0))
        let side = max(1, floor(min((size.width - gutter) / across, (size.height - header) / CGFloat(rows))))
        return Layout(rows: rows, columns: columns, rowColumn: rowColumn, gutter: gutter, header: header, cell: CGSize(width: side, height: side),
                      origin: max(0, floor((size.width - gutter - side * across) / 2)), pane: size)
    }

    /// The week days over their columns.
    private func header(_ layout: Layout) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<layout.columns, id: \.self) { column in
                let weekend = weekendColumn(column)
                Text(columnTitle(column, narrow: layout.cell.width < 56)).font(.caption).lineLimit(1)
                    .foregroundStyle(weekend ? AnyShapeStyle(.indigo) : AnyShapeStyle(.secondary))
                    .bold(isToday(column: column))
                    .frame(width: layout.cell.width)
            }
            if layout.rowColumn {
                Text("Week").font(.caption).foregroundStyle(.secondary).frame(width: layout.cell.width)
            }
        }
        .frame(height: layout.header)
        .accessibilityHidden(true)
    }

    private func columnTitle(_ column: Int, narrow: Bool) -> String {
        if page.period == .month { return calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + column) % 7] }
        return Date(timeIntervalSince1970: page.interval.start.timeIntervalSince1970 + Double(column) * 86_400 + 43_200)
            .formatted(.dateTime.weekday(narrow ? .narrow : .abbreviated).day())
    }

    private func columnCell(_ column: Int) -> CalendarCell? { page.grid.compactMap { $0[column] }.first }

    private func weekendColumn(_ column: Int) -> Bool {
        columnCell(column).map { calendar.isDateInWeekend(Date(timeIntervalSince1970: $0.start)) } ?? false
    }

    private func isToday(column: Int) -> Bool {
        page.period == .week && columnCell(column).map { calendar.isDateInToday(Date(timeIntervalSince1970: $0.start)) } == true
    }

    /// The hour each row of a Week starts, in the shown zone and in the extra zones.
    private func gutter(_ layout: Layout) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Color.clear.frame(height: layout.header)
            ForEach(page.grid.indices, id: \.self) { row in
                VStack(alignment: .trailing, spacing: 1) {
                    if let start = page.grid[row].compactMap({ $0 }).first?.start {
                        ForEach(Array(([calendar.timeZone] + extras).enumerated()), id: \.offset) { i, zone in
                            Text(AppTime.namedHour(start, in: zone)).foregroundStyle(i == 0 ? .primary : .secondary)
                                .font(i == 0 ? .caption2 : .system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .font(.caption2)
                .padding(.trailing, 6)
                .frame(width: layout.gutter, height: layout.cell.height, alignment: .topTrailing)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Cells

    private func position(of start: Double) -> (row: Int, column: Int)? {
        for (row, cells) in page.grid.enumerated() {
            if let column = cells.firstIndex(where: { $0?.start == start }) { return (row, column) }
        }
        return nil
    }

    private func fill(_ cell: CalendarCell?) -> Color {
        guard let cell, page.period == .month || page.period == .week else { return .clear }
        let date = Date(timeIntervalSince1970: cell.start)
        if calendar.isDateInToday(date) { return Color.primary.opacity(scheme == .dark ? 0.12 : 0.08) }
        return calendar.isDateInWeekend(date) ? Color.indigo.opacity(scheme == .dark ? 0.09 : 0.05) : .clear
    }

    private func cells(_ layout: Layout, colors: [AppKey: Color]) -> some View {
        let hairline = 1 / displayScale
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(page.grid.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(page.grid[row].indices, id: \.self) { column in
                            cellView(page.grid[row][column], row: row, column: column, layout)
                        }
                        if layout.rowColumn { rowView(row, layout) }
                    }
                }
            }
            hover(layout)
            selectionOutline(layout)
            separators(layout, hairline)
            monthEdge(layout)
            input(layout)
        }
        .frame(width: layout.width, height: layout.height)
        .previewBeside(previewPoint(layout), clearing: page.period.selectsBars ? 0 : layout.cell.width,
                      within: CGRect(x: -(layout.origin + layout.gutter), y: -layout.header, width: layout.pane.width, height: layout.pane.height)) {
            preview(colors: colors)
        }
    }

    @ViewBuilder private func cellView(_ cell: CalendarCell?, row: Int, column: Int, _ layout: Layout) -> some View {
        let selected = cell.map { cell in
            page.period.selectsBars ? selectedBars(in: cell) != nil : model.selected?.contains(cell.start) == true
        } ?? false
        ZStack {
            fill(cell)
            if let cell {
                CalendarCellView(cell: cell, page: page, footer: footer, extras: extras,
                                 marked: marked(cell), selected: selectedBars(in: cell), width: layout.cell.width)
            } else if page.period == .month {
                // A day of the month before or after: its number only.
                Text(outsideDay(row: row, column: column)).font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(ActivityMonitorX.Layout.inset)
            }
        }
        .frame(width: layout.cell.width, height: layout.cell.height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(cell == nil)
        .accessibilityLabel(cell.map(describe) ?? "")
        .accessibilityValue(cell.flatMap(barValue) ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .adjustable(page.period.selectsBars && cell != nil) { direction in if let cell { moveBar(in: cell, direction) } }
        .accessibilityAction { if let cell, cell.value != nil { let at = target(cell); model.select(at, at) } }
        .accessibilityAction(named: "Extend Selection") { if let cell, cell.value != nil { let at = target(cell); model.select(at, at, extending: model.selected) } }
        .accessibilityAction(named: "Zoom In") { if let cell, cell.value != nil { model.zoomIn(at: cell.start) } }
        .accessibilityAction(named: "Show in Apps") { if let cell, cell.value != nil { selection.reveal(from: cell.start, to: cell.end, history: history) } }
    }

    // MARK: Bars

    private func bars(of cell: CalendarCell) -> [Int] { cell.lines.indices.filter { cell.lines[$0] != nil } }

    /// The lines of `cell` inside the selected span (Day and Hour).
    private func selectedBars(in cell: CalendarCell) -> ClosedRange<Int>? {
        guard page.period.selectsBars, let span = model.selected else { return nil }
        let low = max(0, Int(((span.lowerBound - cell.start) / cell.bucket).rounded(.up)))
        let high = min(cell.lines.count - 1, Int(((span.upperBound - cell.start) / cell.bucket).rounded(.down)))
        return low <= high ? low...high : nil
    }

    /// The line the pointer is on, in the cell it is on.
    private func marked(_ cell: CalendarCell) -> Int? {
        guard let hit = _hover.wrappedValue, hit.hasData, hit.cell.start == cell.start else { return nil }
        return hit.bar
    }

    /// The last selected line of `cell`: the one VoiceOver steps from.
    private func currentBar(_ cell: CalendarCell) -> Int? {
        selectedBars(in: cell).flatMap { range in bars(of: cell).last { range.contains($0) } }
    }

    /// What the default action selects: the cell; in Day and Hour its current line, else its first with data.
    private func target(_ cell: CalendarCell) -> Double {
        page.period.selectsBars ? cell.lineStart(currentBar(cell) ?? bars(of: cell).first ?? 0) : cell.start
    }

    private func barValue(_ cell: CalendarCell) -> String? {
        guard page.period.selectsBars, let bar = currentBar(cell) ?? bars(of: cell).first, let value = cell.lines[bar] else { return nil }
        return "\(Date(timeIntervalSince1970: cell.lineStart(bar)).formatted(.dateTime.hour().minute())): \(page.metric.label) \(page.metric.format(value))"
    }

    /// VoiceOver's adjust gesture: the next or the previous line with data.
    private func moveBar(in cell: CalendarCell, _ direction: AccessibilityAdjustmentDirection) {
        let all = bars(of: cell)
        let current = currentBar(cell)
        let next = direction == .increment ? all.first { $0 > (current ?? -1) } : all.last { $0 < (current ?? cell.lines.count) }
        if let next { model.select(cell.lineStart(next), cell.lineStart(next)) }
    }

    private func outsideDay(row: Int, column: Int) -> String {
        CalendarCellView.dayLabel(day(row: row, column: column)!, calendar: calendar)
    }

    /// The day of a Month position or of a Week column; nil in Day and Hour.
    private func day(row: Int, column: Int) -> Date? {
        let offset: Int
        switch page.period {
        case .month: offset = row * 7 + column - (page.grid[0].firstIndex { $0 != nil } ?? 0)
        case .week: offset = column
        default: return nil
        }
        return calendar.date(byAdding: .day, value: offset, to: page.interval.start)
    }

    /// One step line where the month changes between neighbours (Month: along the cells of the days outside the month;
    /// Week: between the two months' days), over the hairlines.
    private func monthEdge(_ layout: Layout) -> some View {
        func month(_ row: Int, _ column: Int) -> DateComponents? {
            day(row: row, column: column).map { calendar.dateComponents([.year, .month], from: $0) }
        }
        let (w, h) = (layout.cell.width, layout.cell.height)
        return Path { path in
            for row in 0..<layout.rows {
                for column in 0..<layout.columns {
                    let here = month(row, column)
                    if column + 1 < layout.columns, month(row, column + 1) != here {
                        path.move(to: CGPoint(x: CGFloat(column + 1) * w, y: CGFloat(row) * h))
                        path.addLine(to: CGPoint(x: CGFloat(column + 1) * w, y: CGFloat(row + 1) * h))
                    }
                    if row + 1 < layout.rows, month(row + 1, column) != here {
                        path.move(to: CGPoint(x: CGFloat(column) * w, y: CGFloat(row + 1) * h))
                        path.addLine(to: CGPoint(x: CGFloat(column + 1) * w, y: CGFloat(row + 1) * h))
                    }
                }
            }
        }
        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func rowView(_ row: Int, _ layout: Layout) -> some View {
        let cell = page.rows[row]
        let counts = page.counts(page.grid[row].compactMap { $0 })
        ZStack {
            if let cell { CalendarRowView(cell: cell, page: page, counts: counts, severities: page.severities(row: row), width: layout.cell.width) }
        }
        .frame(width: layout.cell.width, height: layout.cell.height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(cell?.value == nil)
        .accessibilityLabel(cell.flatMap { cell in cell.value.map { "Week: \(page.metric.label) \(page.metric.format($0))" } } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select(row: row) }
        .accessibilityAction(named: "Zoom In") { if let cell { model.zoomIn(at: cell.start) } }
    }

    /// The days of a row, from the first to the last that has a cell.
    private func select(row: Int) {
        let cells = page.grid[row].compactMap { $0 }
        if let first = cells.first, let last = cells.last, page.period == .month { model.selected = first.start...last.start }
    }

    // MARK: Layers over the cells

    /// One hairline between neighbours and around the grid.
    private func separators(_ layout: Layout, _ hairline: CGFloat) -> some View {
        Path { path in
            let columns = layout.columns + (layout.rowColumn ? 1 : 0)
            for column in 0...columns {
                path.move(to: CGPoint(x: CGFloat(column) * layout.cell.width, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(column) * layout.cell.width, y: layout.height))
            }
            for row in 0...layout.rows {
                path.move(to: CGPoint(x: 0, y: CGFloat(row) * layout.cell.height))
                path.addLine(to: CGPoint(x: layout.width, y: CGFloat(row) * layout.cell.height))
            }
        }
        .stroke(.separator, lineWidth: hairline)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rect(row: Int, column: Int, _ layout: Layout) -> CGRect {
        CGRect(x: CGFloat(column) * layout.cell.width, y: CGFloat(row) * layout.cell.height, width: layout.cell.width, height: layout.cell.height)
    }

    /// The pointer's cell, in grey: it never looks like the selection.
    @ViewBuilder private func hover(_ layout: Layout) -> some View {
        if let hit = _hover.wrappedValue, !page.period.selectsBars {
            Rectangle().strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: layout.cell.width, height: layout.cell.height)
                .offset(x: CGFloat(hit.column) * layout.cell.width, y: CGFloat(hit.row) * layout.cell.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The selected cells as outline parts. Time runs along a row in Month and Day and down a column in Week: where it
    /// jumps to the next row or column, the sides stay open.
    private func outlineCells(_ layout: Layout) -> [SpanOutline.Cell] {
        let selected = model.selectedCells
        var cells: [SpanOutline.Cell] = []
        for (i, cell) in selected.enumerated() {
            guard let at = position(of: cell.start) else { continue }
            var outline = SpanOutline.Cell(rect: rect(row: at.row, column: at.column, layout))
            if i + 1 < selected.count, let next = position(of: selected[i + 1].start) {
                if page.period == .week, next.column != at.column { outline.open.insert(.bottom) }
                if page.period != .week, next.row != at.row { outline.open.insert(.trailing) }
            }
            if i > 0, let previous = position(of: selected[i - 1].start) {
                if page.period == .week, previous.column != at.column { outline.open.insert(.top) }
                if page.period != .week, previous.row != at.row { outline.open.insert(.leading) }
            }
            cells.append(outline)
        }
        return cells
    }

    /// One accent outline around the selected cells, over a very light accent fill.
    @ViewBuilder private func selectionOutline(_ layout: Layout) -> some View {
        let cells = outlineCells(layout)
        if !cells.isEmpty {
            ZStack {
                SpanOutline.fill(cells).fill(Color.accentColor.opacity(0.09))
                SpanOutline.path(cells).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Pointer

    private func hit(at point: CGPoint, _ layout: Layout) -> Hit? {
        let row = Int(point.y / layout.cell.height), column = Int(point.x / layout.cell.width)
        guard point.x >= 0, point.y >= 0, row < layout.rows else { return nil }
        if column < layout.columns {
            guard let cell = page.grid[row][column] else { return nil }
            guard page.period.selectsBars, !cell.lines.isEmpty else { return Hit(row: row, column: column, low: cell.start, high: cell.start, cell: cell) }
            // The lines run across the cell inside its padding (`CalendarCellView`).
            let pad = ActivityMonitorX.Layout.inset
            let across = (point.x - CGFloat(column) * layout.cell.width - pad) / (layout.cell.width - 2 * pad)
            let bar = min(cell.lines.count - 1, max(0, Int(across * CGFloat(cell.lines.count))))
            return Hit(row: row, column: column, low: cell.lineStart(bar), high: cell.lineStart(bar), cell: cell, bar: bar)
        }
        // The week cell selects the days of its row in Month; in Week it is only a readout.
        guard layout.rowColumn, column == layout.columns, page.period == .month, let cell = page.rows[row],
              let last = page.grid[row].compactMap({ $0 }).last else { return nil }
        return Hit(row: row, column: column, low: cell.start, high: last.start, cell: cell)
    }

    private func input(_ layout: Layout) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(CalendarView.contentSpace)).origin } action: { _inputOrigin.wrappedValue = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    _pointer.wrappedValue = point
                    let hit = hit(at: point, layout)
                    if hit != _hover.wrappedValue { _hover.wrappedValue = hit }
                case .ended:
                    _hover.wrappedValue = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if !_dragging.wrappedValue {
                    _dragging.wrappedValue = true
                    // Shift keeps the selection and extends it to the clicked cell; a click on a time with no data clears it
                    // only without Shift.
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    _base.wrappedValue = shift ? model.selected : nil
                    _anchor.wrappedValue = hit(at: drag.startLocation, layout).flatMap { $0.hasData ? $0 : nil }
                    if _anchor.wrappedValue == nil, !shift { model.selected = nil }
                }
                guard let from = _anchor.wrappedValue else { return }
                let to = hit(at: drag.location, layout) ?? from
                model.select(min(from.low, to.low), max(from.high, to.high), extending: _base.wrappedValue)
            }.onEnded { _ in (_dragging.wrappedValue, _anchor.wrappedValue, _base.wrappedValue) = (false, nil, nil) })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                if let hit = hit(at: tap.location, layout), hit.hasData {
                    model.zoomIn(at: hit.low, from: CGPoint(x: _inputOrigin.wrappedValue.x + tap.location.x, y: _inputOrigin.wrappedValue.y + tap.location.y))
                }
            })
            // The cell under the pointer, as the hover has it when the menu opens.
            .contextMenu {
                if let hit = _hover.wrappedValue, hit.hasData {
                    Group {
                        if let deeper = page.period.zoomedIn {
                            Button("Show \(deeper.rawValue.capitalized)", systemImage: "plus.magnifyingglass") { model.zoomIn(at: hit.cell.start) }
                                .help("Open this \(page.period == .day ? "hour" : "day") in the \(deeper.rawValue) view")
                        }
                        Button("Show in Apps", systemImage: "square.grid.2x2") {
                            selection.reveal(from: hit.cell.start, to: hit.cell.end, history: history)
                        }
                        .help("Show the apps for this time on the Apps screen")
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: Preview

    /// The target's near top corner: the card goes to its right or, with no room, to its left.
    private func previewPoint(_ layout: Layout) -> CGPoint? {
        guard let hit = _hover.wrappedValue, hit.hasData, hit.column < layout.columns else { return nil }
        if page.period.selectsBars { return _pointer.wrappedValue }
        return CGPoint(x: CGFloat(hit.column) * layout.cell.width, y: CGFloat(hit.row) * layout.cell.height)
    }

    @ViewBuilder private func preview(colors: [AppKey: Color]) -> some View {
        if let hit = _hover.wrappedValue, hit.hasData {
            CalendarPreview(page: page, cell: hit.cell, usual: model.usual, colors: colors, extras: extras,
                            line: hit.bar)
        }
    }

    /// The cell's time and value with units, for VoiceOver.
    private func describe(_ cell: CalendarCell) -> String {
        let start = Date(timeIntervalSince1970: cell.start)
        let time = page.period == .month ? start.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        guard let value = cell.value else { return "\(time): no data" }
        var text = "\(time): \(page.metric.label) \(page.metric.format(value))"
        if let app = cell.top.first?.app { text += ", busiest app \(app.name)" }
        if page.status != nil, page.bucket == 3600 || page.metric == .memory {
            let counts = page.counts([cell])
            if counts.critical > 0 { text += ", \(counts.critical) \(page.phrase("critical"))" }
            if counts.warning > 0 { text += ", \(counts.warning) \(page.phrase("warning"))" }
        }
        return text
    }
}

private extension View {
    /// VoiceOver's adjust gesture, only on the elements that step through bars.
    @ViewBuilder func adjustable(_ on: Bool, _ action: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View {
        if on { accessibilityAdjustableAction(action) } else { self }
    }
}
