import SwiftUI

/// The parts of a `PreviewCard`; outside the generic card so a host can build them before it has the chart.
struct PreviewStat {
    let label: String
    let value: String
    var note: String? = nil
    var secondary = false
}

struct PreviewRow {
    /// Warning (1) or critical (2) glyph before the row.
    var severity: Int? = nil
    var swatch: Color? = nil
    var time: String? = nil
    let label: String
    var value: String? = nil
    /// Secondary text, indented under the row above (for example Other's processes).
    var detail = false
}

struct PreviewSection {
    var heading: String? = nil
    let rows: [PreviewRow]
}

/// The one hover preview: a title with its top value, the time span, stats, a mini chart, rows in sections and a hint.
/// Compact fits its content (a chart bubble); large is 380 pt wide. As a hover overlay it takes no pointer events: a
/// popover that follows the pointer flickered when the pointer ran into it (D24, D58). A host with hover only content
/// puts `summary` in the element's accessibility value.
struct PreviewCard<Chart: View>: View {
    enum Size { case compact, large }

    typealias Stat = PreviewStat
    typealias Row = PreviewRow
    typealias Section = PreviewSection

    let size: Size
    let title: String
    var top: String? = nil
    var span: [String] = []
    var stats: [Stat] = []
    var sections: [Section] = []
    var hint: String? = nil
    /// In a real popover (it scrolls and takes clicks): no card background, and the rows scroll past 360 pt.
    var inPopover = false
    @ViewBuilder var chart: Chart

    var body: some View {
        let card = VStack(alignment: .leading, spacing: size == .large ? 8 : 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 8)
                if let top { Text(top).monospacedDigit().fontWeight(.semibold) }
            }
            if !span.isEmpty {
                VStack(alignment: .leading, spacing: 1) { ForEach(span, id: \.self) { Text($0) } }.foregroundStyle(.secondary)
            }
            if !stats.isEmpty {
                HStack(alignment: .top) {
                    ForEach(stats.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stats[i].label).foregroundStyle(.secondary)
                            Text(stats[i].value).font(.title3).fontWeight(.semibold).monospacedDigit()
                                .foregroundStyle(stats[i].secondary ? .secondary : .primary)
                            if let note = stats[i].note { Text(note).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if Chart.self != EmptyView.self { chart.frame(height: 96) }
            if inPopover {
                ScrollView { rows }.frame(maxHeight: 360)
            } else {
                rows
            }
            if let hint { Text(hint).foregroundStyle(.secondary) }
        }
        .font(.caption)
        if inPopover {
            card.padding(12).frame(width: 380).accessibilityElement(children: .contain)
        } else if size == .large {
            card.padding(12).frame(width: 380).glassEffect(.regular, in: .rect(cornerRadius: 10))
                .allowsHitTesting(false).accessibilityHidden(true)
        } else {
            card.fixedSize().padding(8).glassEffect(.regular, in: .rect(cornerRadius: 10))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(sections.indices, id: \.self) { s in
                if let heading = sections[s].heading { Text(heading).foregroundStyle(.secondary).padding(.top, s == 0 ? 0 : 4) }
                ForEach(sections[s].rows.indices, id: \.self) { r in row(sections[s].rows[r]) }
            }
        }
    }

    private func row(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let severity = row.severity { SeverityIcon(severity: severity).imageScale(.small) }
            if let swatch = row.swatch { RoundedRectangle(cornerRadius: 2).fill(swatch).frame(width: 8, height: 8) }
            if let time = row.time { Text(time).monospacedDigit().foregroundStyle(.secondary) }
            Text(row.label).lineLimit(size == .large ? 2 : 1)
            Spacer(minLength: 8)
            if let value = row.value { Text(value).monospacedDigit() }
        }
        .foregroundStyle(row.detail ? .secondary : .primary)
        .padding(.leading, row.detail ? 13 : 0)
    }

    /// The card as text, for the host element's accessibility value.
    var summary: String {
        let lines = [top.map { "\(title), \($0)" } ?? title] + span
            + stats.map { [$0.label, $0.value, $0.note].compactMap { $0 }.joined(separator: " ") }
            + sections.flatMap { s in (s.heading.map { [$0] } ?? []) + s.rows.map { [$0.time, $0.label, $0.value].compactMap { $0 }.joined(separator: " ") } }
            + (hint.map { [$0] } ?? [])
        return lines.joined(separator: ". ")
    }
}

extension PreviewCard where Chart == EmptyView {
    init(size: Size, title: String, top: String? = nil, span: [String] = [], stats: [Stat] = [], sections: [Section] = [],
         hint: String? = nil, inPopover: Bool = false) {
        self.init(size: size, title: title, top: top, span: span, stats: stats, sections: sections, hint: hint, inPopover: inPopover) {
            EmptyView()
        }
    }
}

extension View {
    /// A hover preview beside `point` (in this view's space), on the side with room, and always inside the window's
    /// content: it shifts up or left when the view is too small for it. A `window` point (top left origin) is moved
    /// into this view's space: a table cell cannot name it. A target that starts at `point` and is `clearing` wide (a
    /// grid cell) stays uncovered: the card goes past its far side, or before its near side. `within` (in this view's space) replaces the window as the area the card stays in.
    func previewBeside(_ point: CGPoint?, inWindow: Bool = false, clearing: CGFloat = 0, within: CGRect? = nil,
                       @ViewBuilder card: () -> some View) -> some View {
        let card = card()
        return overlay {
            GeometryReader { geo in
                let host = geo.frame(in: .global)
                // The window's content in this view's space.
                let size = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentView?.bounds.size ?? geo.size
                let bounds = within ?? CGRect(x: -host.minX, y: -host.minY, width: size.width, height: size.height)
                if let point = point.map({ CGPoint(x: $0.x - (inWindow ? host.minX : 0), y: $0.y - (inWindow ? host.minY : 0)) }) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        card
                            .alignmentGuide(.leading) { d in
                                let right = point.x + clearing + 12
                                let x = right + d.width <= bounds.maxX ? right : point.x - 12 - d.width
                                return -max(bounds.minX, min(x, bounds.maxX - d.width))
                            }
                            .alignmentGuide(.top) { d in -max(bounds.minY, min(point.y - 8, bounds.maxY - d.height)) }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
