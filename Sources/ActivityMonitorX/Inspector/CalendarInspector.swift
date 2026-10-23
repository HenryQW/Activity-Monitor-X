import AMXCore
import SwiftUI

/// The selection of the Calendar. One cell: its time, its summary against the usual, its lines, its top apps and alerts.
/// A span: it set against the span of the same length before. In Day and Hour a selection is bars: the span of those bars
/// with its lines and its top apps. Nothing selected: the period at a glance.
struct CalendarInspector: View {
    @Environment(CalendarModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @Environment(GroupsModel.self) private var groups
    /// The apps of the period as last read; nil after a failed read.
    private let _apps = State<[AppRank]?>(initialValue: nil)
    private let _comparison = State<CalendarComparison?>(initialValue: nil)
    private let _reading = State(initialValue: true)

    private struct Read: Equatable {
        let start: Double
        let end: Double
        let metric: Metric
        let filter: CalendarFilter
        let span: Bool
        /// The seconds of the buckets the apps are read from: an hour, or finer for bars.
        var bucket: Double = 3600
    }

    private var group: ProcessGroup? {
        if case .group(let id) = model.show { groups.groups.first { $0.id == id } } else { nil }
    }

    var body: some View {
        if let page = model.page {
            let cells = model.selectedCells
            let colors = AppPalette.colors(for: page.apps, chosen: history.appColors)
            Form {
                if let span = model.selectedBars {
                    bars(span, page, colors)
                } else if let cell = model.selectedCell {
                    single(cell, page, colors)
                } else if cells.count > 1 {
                    span(cells, page)
                } else {
                    summary(page)
                }
            }
            .formStyle(.grouped)
            .task(id: read(page, cells)) { await load(read(page, cells), page) }
        } else {
            ContentUnavailableView("No Selection", systemImage: "calendar",
                                   description: Text("Click a day, an hour or a block of hours to see its details."))
        }
    }

    private func read(_ page: CalendarPage, _ cells: [CalendarCell]) -> Read {
        let filter = CalendarFilter(query: page.filter.query, group: page.filter.group)
        if let span = model.selectedBars {
            return Read(start: span.start, end: span.end, metric: page.metric, filter: filter, span: false, bucket: page.bucket)
        }
        if model.selectedCell != nil { return Read(start: 0, end: 0, metric: page.metric, filter: filter, span: false) }
        if let first = cells.first, let last = cells.last, cells.count > 1 {
            return Read(start: first.start, end: last.end, metric: page.metric, filter: filter, span: true)
        }
        return Read(start: page.interval.start.timeIntervalSince1970, end: page.interval.end.timeIntervalSince1970, metric: page.metric,
                    filter: filter, span: false)
    }

    private func load(_ read: Read, _ page: CalendarPage) async {
        guard read.end > read.start else { return }
        _reading.wrappedValue = true
        if read.span {
            let comparison = await model.compare(start: read.start, end: read.end, metric: read.metric, filter: read.filter)
            guard !Task.isCancelled else { return }
            (_comparison.wrappedValue, _reading.wrappedValue) = (comparison, false)
        } else {
            let apps = await model.apps(from: read.start, to: read.end, metric: read.metric, filter: read.filter, bucket: read.bucket)
            guard !Task.isCancelled else { return }
            (_apps.wrappedValue, _reading.wrappedValue) = (apps, false)
        }
    }

    // MARK: One cell

    @ViewBuilder private func single(_ cell: CalendarCell, _ page: CalendarPage, _ colors: [AppKey: Color]) -> some View {
        let metric = page.metric
        let start = Date(timeIntervalSince1970: cell.start)
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let title = switch page.period {
        case .month: day
        case .week: "\(day), \(start.formatted(.dateTime.hour())) to \(Date(timeIntervalSince1970: cell.end).formatted(.dateTime.hour()))"
        case .day: "\(day), \(start.formatted(.dateTime.hour()))"
        case .hour: "\(day), \(start.formatted(.dateTime.hour().minute())) to \(Date(timeIntervalSince1970: cell.end).formatted(.dateTime.hour().minute()))"
        }
        Section { Text(title).font(.title3.bold()).overlayScrollers() }
        Section("Summary") {
            if let value = cell.value {
                LabeledContent("Average") {
                    VStack(alignment: .trailing) {
                        Text(metric.format(value))
                        if let usual = model.usual?.value(from: cell.start, to: cell.end) {
                            Text("usual \(metric.format(usual)) · \(UsualProfile.describe(value, usual: usual).prefix(1).lowercased() + UsualProfile.describe(value, usual: usual).dropFirst())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let peak = cell.peak {
                LabeledContent("Peak", value: "\(metric.format(cell.lines[peak]!)) at \(Date(timeIntervalSince1970: cell.lineStart(peak)).formatted(page.bucket < 3600 ? .dateTime.hour().minute() : .dateTime.hour()))")
            }
            if page.status != nil, page.bucket == 3600 {
                LabeledContent(page.hoursLabel) {
                    let counts = page.counts([cell])
                    if counts.warning + counts.critical == 0 { Text("None").foregroundStyle(.secondary) } else { LevelCounts(counts: counts) }
                }
            }
        }
        .monospacedDigit()
        Section(page.bucket < 3600 ? "Lines" : "Hours") {
            CalendarLinesChart(cell: cell, page: page, colors: colors)
        }
        Section("Top Apps") {
            if cell.top.isEmpty { Text("No apps").foregroundStyle(.secondary) }
            ForEach(cell.top, id: \.app) { entry in
                LabeledContent {
                    Text(metric.format(entry.value)).monospacedDigit()
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(colors[entry.app] ?? .secondary).frame(width: 9, height: 9)
                        Text(entry.app.name).lineLimit(1)
                    }
                }
            }
        }
        alerts(page.alerts(in: cell))
        Section {
            HStack {
                Spacer()
                if let deeper = page.period.zoomedIn {
                    Button("Open \(deeper.rawValue.capitalized)") { model.zoomIn(at: cell.start) }
                        .help("Show this \(page.period == .month ? "day" : page.period == .week ? "block of hours" : "hour") in the finer period")
                }
                Button("Show in Apps") { selection.reveal(from: cell.start, to: cell.end, history: history) }
                    .buttonStyle(.borderedProminent)
                    .help("Open Apps at this time")
            }
        }
    }

    @ViewBuilder private func alerts(_ events: [EventMark]) -> some View {
        Section(events.isEmpty ? "Alerts" : "Alerts (\(events.count.formatted()))") {
            if events.isEmpty { Text("No alerts").foregroundStyle(.secondary) }
            ForEach(events.prefix(8)) { event in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SeverityIcon(severity: event.severity >= 2 ? 2 : 1)
                    VStack(alignment: .leading) {
                        Text(event.message)
                        Text(Date(timeIntervalSince1970: event.ts).formatted(.dateTime.hour().minute())).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if events.count > 8 { Text("and \(events.count - 8) more").foregroundStyle(.secondary) }
        }
    }

    // MARK: Bars

    /// The selected bars (Day and Hour): the time they cover, their mean and peak, their lines and the apps in them.
    @ViewBuilder private func bars(_ span: (start: Double, end: Double), _ page: CalendarPage, _ colors: [AppKey: Color]) -> some View {
        let metric = page.metric
        let slots = page.cells.flatMap { cell in
            let severities = page.severities(cell)
            return cell.lines.indices.map { (start: cell.lineStart($0), value: cell.lines[$0], severity: severities.indices.contains($0) ? severities[$0] : nil) }
        }
        .filter { span.start <= $0.start && $0.start < span.end }
        let values = slots.compactMap(\.value)
        let peak = slots.filter { $0.value != nil }.max { $0.value! < $1.value! }
        let time = Date.FormatStyle.dateTime.hour().minute()
        let first = Date(timeIntervalSince1970: span.start), last = Date(timeIntervalSince1970: span.end)
        let day = first.formatted(.dateTime.weekday(.wide).day().month(.wide))
        Section { Text("\(day), \(first.formatted(time)) to \(last.formatted(time))").font(.title3.bold()).overlayScrollers() }
        Section("Summary") {
            if !values.isEmpty { LabeledContent("Average", value: metric.format(values.reduce(0, +) / Double(values.count))) }
            if let peak, slots.count > 1 { LabeledContent("Peak", value: "\(metric.format(peak.value!)) at \(Date(timeIntervalSince1970: peak.start).formatted(time))") }
        }
        .monospacedDigit()
        Section("Lines") {
            VStack(spacing: 2) {
                ValueLines(values: slots.map(\.value), top: page.top, status: page.levels, severities: slots.map(\.severity), lineWidth: 6)
                    .frame(height: 70)
                HStack {
                    Text(first.formatted(time))
                    Spacer()
                    Text(last.formatted(time))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lines of the selected time")
        }
        Section("Top Apps") {
            if _reading.wrappedValue {
                ProgressView().frame(maxWidth: .infinity)
            } else if let apps = _apps.wrappedValue {
                if apps.isEmpty { Text("No apps").foregroundStyle(.secondary) }
                ForEach(apps.prefix(5)) { rank in
                    LabeledContent {
                        Text(metric.format(rank.average)).monospacedDigit()
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(colors[rank.app] ?? .secondary).frame(width: 9, height: 9)
                            Text(rank.app.name).lineLimit(1)
                        }
                    }
                }
            } else {
                Text("Cannot read the history").foregroundStyle(.secondary)
            }
        }
        Section {
            HStack {
                Spacer()
                if let deeper = page.period.zoomedIn {
                    Button("Open \(deeper.rawValue.capitalized)") { model.zoomIn(at: span.start) }
                        .help("Show the hour of the first selected bar in the finer period")
                }
                Button("Show in Apps") { selection.reveal(from: span.start, to: span.end, history: history) }
                    .buttonStyle(.borderedProminent)
                    .help("Open Apps at this time")
            }
        }
    }

    // MARK: A span

    @ViewBuilder private func span(_ cells: [CalendarCell], _ page: CalendarPage) -> some View {
        let metric = page.metric
        let first = cells[0], last = cells[cells.count - 1]
        let from = Date(timeIntervalSince1970: first.start), to = Date(timeIntervalSince1970: last.end - 1)
        let format: Date.FormatStyle = page.period == .month ? .dateTime.day().month(.wide) : .dateTime.weekday(.abbreviated).day().hour()
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(from.formatted(format)) to \(to.formatted(format))").font(.title3.bold()).overlayScrollers()
                if let c = _comparison.wrappedValue {
                    let before = Date(timeIntervalSince1970: c.before.start), end = Date(timeIntervalSince1970: c.before.end - 1)
                    Text("Compared with the span of the same length before it (\(before.formatted(format)) to \(end.formatted(format)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if _reading.wrappedValue {
            Section { ProgressView().frame(maxWidth: .infinity) }
        } else if let c = _comparison.wrappedValue {
            Section("Compared") {
                compared("Average", c.now.average.map(metric.format), c.then.average.map(metric.format), delta(c.now.average, c.then.average))
                compared("Peak", c.now.peak.map(metric.format), c.then.peak.map(metric.format), delta(c.now.peak, c.then.peak))
                if page.status != nil {
                    LabeledContent(page.hoursLabel) {
                        VStack(alignment: .trailing) {
                            let now = (c.now.warning, c.now.critical), then = (c.then.warning, c.then.critical)
                            if now.0 + now.1 == 0 { Text("None") } else { LevelCounts(counts: (now.0, now.1)) }
                            HStack(spacing: 3) {
                                Text("was")
                                if then.0 + then.1 == 0 { Text("none") } else { LevelCounts(counts: (then.0, then.1)) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .monospacedDigit()
            Section(c.now.units.count > 24 || cells.count > 24 ? "By Day" : "By Hour") {
                PairBars(now: c.now.units, before: c.then.units)
                    .frame(height: 80)
                HStack {
                    Text(from.formatted(format))
                    Spacer()
                    Text(to.formatted(format))
                }
                .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("Before", systemImage: "square.fill").foregroundStyle(.secondary)
                    Label("Selected", systemImage: "square.fill").foregroundStyle(Color.accentColor)
                }
                .font(.caption2)
                .labelStyle(.titleAndIcon)
            }
            Section("Biggest Changes") {
                if c.change.up.isEmpty && c.change.down.isEmpty { Text("No changes").foregroundStyle(.secondary) }
                ForEach(c.change.up + c.change.down, id: \.app) { change in
                    LabeledContent(change.app.name, value: (change.delta > 0 ? "+" : "-") + metric.format(abs(change.delta))).monospacedDigit()
                }
            }
        } else {
            Section { Text("Cannot read the history").foregroundStyle(.secondary) }
        }
        Section {
            HStack {
                Spacer()
                Button("Show in Apps") { selection.reveal(from: first.start, to: last.end, history: history) }
                    .buttonStyle(.borderedProminent)
                    .help("Open Apps over this span")
            }
        }
    }

    private func delta(_ now: Double?, _ then: Double?) -> String? {
        guard let now, let then, then > 0 else { return nil }
        let change = (now / then - 1).formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        return change
    }

    private func compared(_ title: String, _ now: String?, _ then: String?, _ change: String?) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing) {
                Text(now ?? "No data")
                if let then { Text("was \(then)\(change.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Nothing selected

    /// The period's mean of its cells with data, its busiest cell (a click selects it), its alerts and its top apps.
    @ViewBuilder private func summary(_ page: CalendarPage) -> some View {
        let cells = page.cells.filter { $0.value != nil }
        let busiest = cells.max { $0.value! < $1.value! }
        let unit = page.period == .month ? "day" : page.period == .week ? "block" : "hour"
        Section { Text("\(page.period.rawValue.capitalized) Summary").font(.title3.bold()).overlayScrollers() }
        Section(page.metric.label) {
            LabeledContent("Average", value: cells.isEmpty ? "No data"
                           : page.metric.format(cells.flatMap(\.lines).compactMap { $0 }.reduce(0, +) / Double(cells.flatMap(\.lines).compactMap { $0 }.count)))
            if let busiest {
                // With bars (Day and Hour) the busiest hour is all its bars.
                Button { model.selected = busiest.start...(page.period.selectsBars ? busiest.lineStart(busiest.lines.count - 1) : busiest.start) } label: {
                    LabeledContent("Busiest \(unit)", value: Date(timeIntervalSince1970: busiest.start)
                        .formatted(page.period == .month ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                   : .dateTime.weekday(.abbreviated).day().hour()))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select the busiest \(unit)")
            }
            LabeledContent("Alerts", value: page.alerts.count.formatted())
                .help("The alerts in this \(page.period.rawValue)")
        }
        .monospacedDigit()
        Section {
            if _reading.wrappedValue {
                ProgressView().frame(maxWidth: .infinity)
            } else if let apps = _apps.wrappedValue {
                let colors = AppPalette.colors(for: apps.map(\.app), chosen: history.appColors)
                if apps.isEmpty { Text("No apps").foregroundStyle(.secondary) }
                ForEach(apps.prefix(5)) { rank in
                    LabeledContent {
                        Text(page.metric.format(rank.average)).monospacedDigit()
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(colors[rank.app] ?? .secondary).frame(width: 9, height: 9)
                            Text(rank.app.name).lineLimit(1)
                        }
                    }
                }
            } else {
                Text("Cannot read the history").foregroundStyle(.secondary)
            }
        } header: {
            Text("Top Apps")
        } footer: {
            Text(page.period == .month ? "Click a day to see its details, or drag across days to compare them with the days before."
                 : page.period.selectsBars ? "Click a bar to see its details, or drag across bars to select a span of time."
                 : "Click a cell to see its details, or drag across cells to compare them with the time before.")
        }
    }
}

/// The lines of the selected cell, large: the pointer on a line shows its preview, a click on an hour opens it.
private struct CalendarLinesChart: View {
    @Environment(CalendarModel.self) private var model
    @Environment(Preferences.self) private var preferences
    let cell: CalendarCell
    let page: CalendarPage
    let colors: [AppKey: Color]
    private let _hover = State<(index: Int, point: CGPoint)?>(initialValue: nil)

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ValueLines(values: cell.lines, top: page.top, status: page.levels, severities: page.severities(cell), lineWidth: 6,
                           marked: _hover.wrappedValue?.index)
                    .overlay {
                        Color.clear.contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let point):
                                    let count = cell.lines.count
                                    _hover.wrappedValue = count > 0 ? (min(count - 1, Int(point.x / geo.size.width * CGFloat(count))), point) : nil
                                case .ended: _hover.wrappedValue = nil
                                }
                            }
                            .onTapGesture { location in
                                // An hour line opens the hour; finer lines have nothing finer.
                                guard page.bucket == 3600, !cell.lines.isEmpty else { return }
                                model.open(.hour, at: cell.lineStart(min(cell.lines.count - 1, Int(location.x / geo.size.width * CGFloat(cell.lines.count)))))
                            }
                    }
            }
            .frame(height: 70)
            .previewBeside(_hover.wrappedValue.map(\.point)) {
                if let hover = _hover.wrappedValue, cell.lines[hover.index] != nil {
                    CalendarPreview(page: page, cell: cell, usual: nil, colors: colors, extras: [], line: hover.index)
                }
            }
            HStack {
                ForEach([0.0, 0.5, 1], id: \.self) { fraction in
                    if fraction > 0 { Spacer(minLength: 0) }
                    Text(Date(timeIntervalSince1970: cell.start + fraction * (cell.end - cell.start))
                        .formatted(cell.end - cell.start <= 7200 ? .dateTime.hour().minute() : .dateTime.hour()))
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.bucket < 3600 ? "Lines of this hour" : "Lines of each hour")
    }
}

/// Two bars per unit: the span before in grey and the selected span in the accent.
private struct PairBars: View {
    let now: [Double?]
    let before: [Double?]

    var body: some View {
        Canvas { context, size in
            guard !now.isEmpty else { return }
            let top = max((now + before).compactMap { $0 }.max() ?? 1, 1), slot = size.width / CGFloat(now.count)
            func bar(_ value: Double?, _ x: CGFloat, _ width: CGFloat, _ color: Color) {
                guard let value else { return }
                let height = max(1, CGFloat(value / top) * (size.height - 2))
                context.fill(Path(roundedRect: CGRect(x: x, y: size.height - height, width: width, height: height), cornerRadius: 1.5), with: .color(color))
            }
            for i in now.indices {
                let x = CGFloat(i) * slot + slot * 0.1, width = slot * 0.38
                bar(i < before.count ? before[i] : nil, x, width, .secondary.opacity(0.55))
                bar(now[i], x + width + 1, width, .accentColor)
            }
        }
        .accessibilityHidden(true)
    }
}
