import AMXCore
import SwiftUI

/// The Calendar screen: the metric summed over all apps for each hour of a day or a week (a month day is the mean of its hours), shaded
/// from low to high in the tint. A cell with data opens Apps on its time. Range does not apply here.
struct CalendarView: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection

    /// What a load reads; a new value starts the screen's task again. Each period has its own intervals.
    private struct Load: Equatable {
        let interval: DateInterval
        let metric: Metric
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Calendar")
        .navigationSubtitle(title(model.period, model.interval))
        .task(id: Load(interval: model.interval, metric: history.metric)) { await model.run(metric: history.metric) }
        .onChange(of: selection.refreshes) { Task { await model.load(metric: history.metric) } }
    }

    private var header: some View {
        let name = model.period.label.lowercased()
        return HStack {
            Picker("Period", selection: Bindable(model).period) {
                ForEach(CalendarPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Choose the period")
            Spacer()
            ControlGroup {
                Button("Previous \(model.period.label)", systemImage: "chevron.left") { model.step(-1) }
                    .labelStyle(.iconOnly)
                    .disabled(!model.canStep(-1))
                    .help("Show the previous \(name)")
                Button("Today") { model.anchor = Date() }
                    .disabled(!model.canStep(1))
                    .help("Show the \(name) that holds today")
                Button("Next \(model.period.label)", systemImage: "chevron.right") { model.step(1) }
                    .labelStyle(.iconOnly)
                    .disabled(!model.canStep(1))
                    .help("Show the next \(name)")
            }
            .fixedSize()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed:
            HelperUnavailable()
        case .empty:
            ContentUnavailableView("No Data", systemImage: "calendar",
                                   description: Text("No history was recorded in this \(model.period.label.lowercased())."))
        case .ready:
            if let page = model.page { grid(page) }
        }
    }

    private func grid(_ page: CalendarPage) -> some View {
        let top = page.grid.joined().compactMap { $0?.value }.max() ?? 0
        let hourly = page.period != .month
        return VStack(spacing: 8) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    if hourly { Color.clear.frame(width: Self.labelWidth, height: 0) }
                    ForEach(Array(columnTitles(page).enumerated()), id: \.offset) { _, title in
                        let today = page.period != .month && title == todayTitle
                        Text(title).font(.caption).bold(today).foregroundStyle(today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)).lineLimit(1)
                    }
                }
                ForEach(page.grid.indices, id: \.self) { row in
                    GridRow {
                        if hourly { hourLabel(row) }
                        ForEach(page.grid[row].indices, id: \.self) { column in
                            cell(page.grid[row][column], page: page, top: top)
                        }
                    }
                }
            }
            legend(page.metric, top: top)
        }
        .padding([.horizontal, .bottom])
    }

    private static let labelWidth = 44.0

    /// Today as `columnTitles` writes a Day or Week column.
    private var todayTitle: String { Date().formatted(.dateTime.weekday(.abbreviated).day()) }

    /// Every third hour, as an overlay: a label never sets the height of a row.
    private func hourLabel(_ hour: Int) -> some View {
        Color.clear.frame(width: Self.labelWidth).overlay(alignment: .trailing) {
            if hour % 3 == 0 {
                // Gregorian: a year 2001 date can be nil in another calendar; the hour is the same.
                Text(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour))!.formatted(.dateTime.hour()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }

    /// Day and Week: each day; Month: the weekdays from the locale's first weekday.
    private func columnTitles(_ page: CalendarPage) -> [String] {
        let calendar = Calendar.current
        if page.period == .month {
            let symbols = calendar.shortWeekdaySymbols
            return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        }
        return page.grid[0].indices.map {
            calendar.date(byAdding: .day, value: $0, to: page.interval.start)!.formatted(.dateTime.weekday(.abbreviated).day())
        }
    }

    @ViewBuilder private func cell(_ cell: CalendarCell?, page: CalendarPage, top: Double) -> some View {
        if let cell {
            let label = describe(cell, page)
            Button { selection.reveal(from: cell.start, to: cell.end, history: history) } label: {
                shape(cell.value, top: top, radius: 3)
                    .overlay(alignment: .topLeading) {
                        if page.period == .month {
                            let day = Date(timeIntervalSince1970: cell.start)
                            let today = Calendar.current.isDateInToday(day)
                            Text(day.formatted(.dateTime.day())).font(.caption)
                                .bold(today).foregroundStyle(today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)).padding(4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(cell.value == nil)
            .help(label)
            .accessibilityLabel(label)
        } else {
            Color.clear
        }
    }

    /// The tint from 25% opacity at 0 to full at the period's highest value; a time without data is an outline only.
    @ViewBuilder private func shape(_ value: Double?, top: Double, radius: Double) -> some View {
        if let value {
            RoundedRectangle(cornerRadius: radius).fill(.tint.opacity(0.25 + 0.75 * (top > 0 ? value / top : 0)))
        } else {
            RoundedRectangle(cornerRadius: radius).strokeBorder(.separator)
        }
    }

    private func legend(_ metric: Metric, top: Double) -> some View {
        HStack(spacing: 4) {
            swatch(nil, top: top)
            Text("No data").padding(.trailing, 12)
            Text(metric.format(0))
            ForEach([0, 0.25, 0.5, 0.75, 1], id: \.self) { swatch(top * $0, top: top) }
            Text(metric.format(top))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shade from \(metric.format(0)) to \(metric.format(top)); an outlined cell has no data")
    }

    private func swatch(_ value: Double?, top: Double) -> some View {
        shape(value, top: top, radius: 2).frame(width: 12, height: 12)
    }

    /// The cell's time and value with units, for VoiceOver and the hover tooltip.
    private func describe(_ cell: CalendarCell, _ page: CalendarPage) -> String {
        let start = Date(timeIntervalSince1970: cell.start)
        let time = page.period == .month ? start.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        return "\(time): " + (cell.value.map { "\(page.metric.label) \(page.metric.format($0))" } ?? "no data")
    }

    private func title(_ period: CalendarPeriod, _ interval: DateInterval) -> String {
        switch period {
        case .day: return interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) to \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month: return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }
}

private extension CalendarPeriod {
    var label: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}
