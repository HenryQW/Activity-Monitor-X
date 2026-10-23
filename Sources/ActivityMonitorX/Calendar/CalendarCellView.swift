import AMXCore
import SwiftUI

/// What the foot of a Month or Week cell names.
enum CalendarFooter {
    case none, busiest
    case group(ProcessGroup)
}

/// The inside of one Calendar cell: its value, one line per bucket, and what it names at the foot. Day and week text style
/// follow the period; a time with no data says so, a time to come stays empty.
struct CalendarCellView: View {
    let cell: CalendarCell
    let page: CalendarPage
    let colors: [AppKey: Color]
    let footer: CalendarFooter
    /// The zones whose hours a Day cell lists under its own.
    let extras: [TimeZone]
    /// A line to mark: the one under the pointer.
    var marked: Int?
    /// The lines the selection covers (Day and Hour).
    var selected: ClosedRange<Int>?
    /// The width of the cell; a narrow cell drops, in order, the busiest app's name, its value and the counts.
    var width: CGFloat = .infinity

    /// The inset of the content; the pointer hit test in `CalendarGrid` reads the same value.
    static func padding(_ period: CalendarPeriod, width: CGFloat) -> CGFloat { period == .day || width < 64 ? 3 : 5 }

    private var showsName: Bool { width >= 80 }
    private var showsPeak: Bool { width >= 72 }
    private var showsCounts: Bool { width >= 64 }
    private var showsValue: Bool { width >= 56 }
    private var metric: Metric { page.metric }
    private var future: Bool { cell.start >= Date().timeIntervalSince1970 }
    private var counts: (warning: Int, critical: Int) { page.bucket == 3600 || metric == .memory ? page.counts([cell]) : (0, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch page.period {
            case .month: month
            case .week: block
            case .day: hour
            case .hour: big
            }
        }
        .font(.caption)
        .padding(Self.padding(page.period, width: width))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var value: some View {
        Text(showsValue ? cell.value.map(metric.format) ?? "" : "").fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }

    private var lines: some View {
        ValueLines(values: cell.lines, top: page.top, status: page.levels, severities: page.severities(cell),
                   lineWidth: page.period == .month ? 3 : page.period == .week ? 8 : 3, marked: marked, selected: selected)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var noData: some View {
        if !future && showsCounts { Text("No data").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { Spacer() }
    }

    /// The busiest app, or the group, with its colour.
    @ViewBuilder private var named: some View {
        switch footer {
        case .none: EmptyView()
        case .busiest:
            if let app = cell.top.first?.app { dotted(app.name, colors[app] ?? .secondary) }
        case .group(let group):
            dotted(group.name, group.color.color)
        }
    }

    private func dotted(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            if showsName { Text(name).lineLimit(1) }
        }
        .font(.caption2)
    }

    // MARK: Layouts

    /// A Month cell's day number; the first of a month names its month ("Nov 1").
    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        return day == 1 ? date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day()) : day.formatted()
    }

    @ViewBuilder private var month: some View {
        HStack(spacing: 4) {
            Text(Self.dayLabel(Date(timeIntervalSince1970: cell.start), calendar: page.calendar)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            value
        }
        if cell.value == nil {
            noData
        } else {
            lines
            HStack(spacing: 4) {
                named
                Spacer(minLength: 0)
                if showsCounts { LevelCounts(counts: counts).font(.caption2) }
            }
        }
    }

    @ViewBuilder private var block: some View {
        if cell.value == nil {
            noData
        } else {
            HStack(spacing: 4) {
                value
                Spacer(minLength: 0)
                if showsCounts { LevelCounts(counts: counts).font(.caption2) }
            }
            lines
            HStack(spacing: 4) {
                named
                Spacer(minLength: 0)
                if showsPeak, let peak = cell.peak { Text(metric.format(cell.lines[peak]!)).foregroundStyle(.secondary).font(.caption2).monospacedDigit().lineLimit(1).fixedSize() }
            }
        }
    }

    @ViewBuilder private var hour: some View {
        let start = Date(timeIntervalSince1970: cell.start)
        HStack(spacing: 4) {
            Text(start.formatted(.dateTime.hour())).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if width >= 96 {
                LevelCounts(counts: counts).font(.caption2)
                value
            }
        }
        ForEach(extras, id: \.identifier) { zone in
            Text(AppTime.namedHour(cell.start, in: zone)).font(.caption2).foregroundStyle(.secondary)
        }
        if cell.value == nil { noData } else { lines }
    }

    @ViewBuilder private var big: some View {
        let start = Date(timeIntervalSince1970: cell.start)
        HStack {
            Text(start.formatted(.dateTime.hour())).font(.title3).fontWeight(.semibold)
            Spacer(minLength: 0)
            value.font(.title3)
        }
        if cell.value == nil {
            noData
        } else {
            lines
            HStack {
                ForEach([0.0, 0.5, 1], id: \.self) { fraction in
                    if fraction > 0 { Spacer(minLength: 0) }
                    Text(Date(timeIntervalSince1970: cell.start + fraction * (cell.end - cell.start)).formatted(.dateTime.hour().minute()))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            HStack {
                named
                Spacer(minLength: 0)
                LevelCounts(counts: page.counts([cell])).font(.caption2)
            }
        }
    }
}

/// The cell at the end of a row: the week's mean, its days as lines and the counts of buckets over a level.
struct CalendarRowView: View {
    let cell: CalendarCell
    let page: CalendarPage
    let counts: (warning: Int, critical: Int)
    var severities: [Int?] = []
    var width: CGFloat = .infinity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(width >= 56 ? cell.value.map(page.metric.format) ?? "" : "").fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            if cell.value != nil {
                ValueLines(values: cell.lines, top: page.top, status: page.levels, severities: severities, lineWidth: 8)
                    .frame(maxHeight: .infinity)
                if width >= 64 { HStack { Spacer(minLength: 0); LevelCounts(counts: counts).font(.caption2) } }
            }
        }
        .font(.caption)
        .padding(width < 64 ? 3 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
