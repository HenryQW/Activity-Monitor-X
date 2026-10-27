import AMXCore
import SwiftUI

/// The hover preview of a Calendar cell, in the shared `PreviewCard`: large for a day or a block of hours, compact for an
/// hour or one line of the hour.
struct CalendarPreview: View {
    let page: CalendarPage
    let cell: CalendarCell
    let usual: CalendarUsual?
    let colors: [AppKey: Color]
    /// The zones whose hours the card lists next to the shown zone's.
    let extras: [TimeZone]
    /// A line of the cell (Hour): the card is compact and names that line.
    var line: Int?

    private var metric: Metric { page.metric }
    private var zone: TimeZone { page.calendar.timeZone }

    var body: some View {
        if let line {
            compactLine(line)
        } else if page.period == .day {
            compactHour
        } else {
            large
        }
    }

    // MARK: Time

    private func abbreviation(_ zone: TimeZone) -> String { ZoneLabel.abbreviation(zone, at: Date(timeIntervalSince1970: cell.start)) }

    /// "6 PM HKT" for the shown zone then each extra zone.
    private func inZones(_ time: Double) -> [String] {
        ([zone] + extras).map { "\(AppTime.hour(time, in: $0)) \(abbreviation($0))" }
    }

    private var title: String {
        let text = Date(timeIntervalSince1970: cell.start).formatted(.dateTime.weekday(.wide).day().month(.wide))
        return page.period == .month ? text : "\(text), \(AppTime.hour(cell.start, in: zone)) to \(AppTime.hour(cell.end, in: zone))"
    }

    private var spanLines: [String] {
        if page.period == .month {
            return ["\(metric.label) per hour, \(AppTime.hour(cell.start, in: zone)) to \(AppTime.hour(cell.end, in: zone)) \(abbreviation(zone))"]
        }
        return ([zone] + extras).map { "\(abbreviation($0)) \(AppTime.hour(cell.start, in: $0)) to \(AppTime.hour(cell.end, in: $0))" }
    }

    // MARK: Large

    private var large: some View {
        var stats = [PreviewStat(label: "Average", value: cell.value.map(metric.format) ?? "No data")]
        if let peak = cell.peak {
            stats.append(PreviewStat(label: "Peak", value: metric.format(cell.lines[peak]!),
                                     note: "at " + inZones(cell.lineStart(peak)).joined(separator: " · ")))
        }
        if let usual = usual?.value(from: cell.start, to: cell.end), let value = cell.value {
            let weekday = Date(timeIntervalSince1970: cell.start).formatted(.dateTime.weekday(.abbreviated))
            let block = page.period == .week ? " \(AppTime.hour(cell.start, in: zone)) to \(AppTime.hour(cell.end, in: zone))" : ""
            stats.append(PreviewStat(label: "Usual \(weekday)\(block)", value: metric.format(usual),
                                     note: UsualProfile.describe(value, usual: usual), secondary: true))
        }
        let apps = cell.top.map { PreviewRow(swatch: colors[$0.app], label: $0.app.name, value: metric.format($0.value)) }
        var sections = [PreviewSection(heading: "Busiest by \(metric.label)", rows: apps + unrecorded)]
        let alerts = alertRows
        if !alerts.isEmpty { sections.append(PreviewSection(heading: "Alerts", rows: alerts)) }
        let hint = "Click to select · double-click to open the \(page.period.zoomedIn?.rawValue ?? "hour")"
        return PreviewCard(size: .large, title: title, span: spanLines, stats: stats, sections: sections, hint: hint) {
            VStack(spacing: 2) {
                ValueLines(values: cell.lines, top: page.top, status: page.levels, severities: page.severities(cell),
                           lineWidth: page.period == .month ? 8 : 22)
                axis
            }
        }
    }

    /// The hour labels under the lines: every six hours of a day, every two of a block.
    private var axis: some View {
        let step = page.period == .month ? 6.0 : 2.0
        let times = Array(stride(from: cell.start, through: cell.end, by: step * 3600))
        return HStack {
            ForEach(times.indices, id: \.self) { i in
                if i > 0 { Spacer(minLength: 0) }
                Text(AppTime.hour(times[i], in: zone)).foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    /// The buckets at each level, with their hours, then the first alerts of the cell.
    private var alertRows: [PreviewRow] {
        var rows: [PreviewRow] = []
        if let status = page.status, page.bucket == 3600 {
            let severities = status.severities(cell)
            for (severity, name) in [(2, "critical"), (1, "warning")] {
                let hours = severities.indices.filter { severities[$0] == severity }.map { AppTime.hour(cell.lineStart($0), in: zone) }
                if !hours.isEmpty {
                    rows.append(PreviewRow(severity: severity, label: "\(hours.count) \(hours.count == 1 ? "hour" : "hours") \(page.phrase(name)): "
                                           + hours.joined(separator: ", ")))
                }
            }
        }
        let events = page.alerts(in: cell)
        for event in events.prefix(3) {
            rows.append(PreviewRow(severity: event.severity >= 2 ? 2 : 1,
                                   time: Date(timeIntervalSince1970: event.ts).formatted(.dateTime.hour().minute()), label: event.message))
        }
        if events.count > 3 { rows.append(PreviewRow(label: "and \(events.count - 3) more", detail: true)) }
        return rows
    }

    /// The Mac's CPU that no recorded process accounts for, where the cell's value is the Mac's (CB1): the app rows then
    /// add up to less than the value.
    private var unrecorded: [PreviewRow] {
        guard let value = cell.value, let recorded = cell.recorded, value - recorded >= 1 else { return [] }
        return [PreviewRow(label: "Not in any process", value: metric.format(value - recorded))]
    }

    // MARK: Compact

    private func appRows(_ apps: [CellApp]) -> [PreviewSection] {
        [PreviewSection(rows: apps.map { PreviewRow(swatch: colors[$0.app], label: $0.app.name, value: metric.format($0.value)) })]
    }

    private var compactHour: some View {
        let time = Date(timeIntervalSince1970: cell.start).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour())
        return PreviewCard(size: .compact, title: time, top: cell.value.map(metric.format),
                           sections: [PreviewSection(rows: appRows(cell.top)[0].rows + unrecorded)])
    }

    private func compactLine(_ line: Int) -> some View {
        let time = Date(timeIntervalSince1970: cell.lineStart(line))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        let leader = line < cell.leaders.count ? cell.leaders[line] : nil
        return PreviewCard(size: .compact, title: time, top: cell.lines[line].map(metric.format),
                           sections: appRows(leader.map { [$0] } ?? []))
    }
}
