import AMXCore
import AppKit
import SwiftUI

/// The Apps screen: the chart above the app table, or the table alone while Show Chart is off. With `focus`, one pinned
/// app: its single area and its processes. With `group`, the history model is scoped to the group's members, and the
/// table shows each app's share of the group. Both always show the chart.
struct TimelineView: View {
    let focus: AppKey?
    var group: ProcessGroup? = nil
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection
    @AppStorage("settingsTab") private var settingsTab = "general"
    @Environment(\.openSettings) private var openSettings
    /// The app key under the pointer in the legend or the table ("" for Other): its band stays, the others dim.
    private let _hovered = State<String?>(initialValue: nil)
    /// The content is tall enough for the chart, the metric footer and a useful table.
    private let _tall = State(initialValue: true)

    var body: some View {
        // Live shows once it has its own data; until then the range before it stays on screen, so Start Live never blanks it.
        let isLive = history.range == .live && !(live.state == .loading && history.state == .ready)
        let points = focus.map { isLive ? live.series(of: $0) : history.series(of: $0) }
            ?? (isLive ? live.stacked : history.stacked)
        let ranking = focus.map { app in (isLive ? live.rank(of: app) : history.rank(of: app)).map { [$0] } ?? [] }
            ?? (isLive ? live.ranking : history.ranking)
        let shown = AppSearch.filter(ranking, query: selection.search)
        let colors = AppPalette.colors(for: points, chosen: history.appColors)
        let title = focus.map { AppName.display($0, history: history) } ?? group?.name
        // The hovered app, else the app the inspector shows with a softer dim: its band stays, the others dim.
        let emphasised = _hovered.wrappedValue ?? (selection.inspectorShown ? selection.app?.key : nil)
        let banded = emphasised.map { key in key == "" || colors.keys.contains { $0.key == key } } == true
        // An emphasised app without a band: dim every band and draw its own series over them.
        let bandless = banded ? nil : emphasised.flatMap { key in ranking.first { $0.app.key == key }?.app }
        let chart = title != nil || selection.showChart
        // Apps only: the footer is the whole system's, and Show Chart hides it with the chart.
        let footer = title == nil && chart && _tall.wrappedValue && history.metric != .score
        Group {
            switch isLive ? live.state : history.state {
            case .loading:
                ProgressView()
            case .empty:
                collecting
            case .failed:
                HelperUnavailable()
            case .ready where points.isEmpty:
                if let title {
                    ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line",
                                           description: Text("\(title) has no data in this range."))
                } else {
                    collecting
                }
            case .ready:
                VStack(spacing: 0) {
                    if chart {
                        TimelineChart(points: points, colors: colors, bucket: isLive ? 1 : history.loadedBucket, live: isLive, metric: history.metric,
                                      events: isLive ? [] : history.events,
                                      highlighted: banded ? [emphasised!] : bandless != nil ? []
                                          : selection.search.isEmpty ? nil : Set(shown.map(\.app.key)),
                                      dim: _hovered.wrappedValue == nil && (banded || bandless != nil) ? 0.5 : 0.25,
                                      line: bandless.map { isLive ? live.series(of: $0) : history.series(of: $0) },
                                      span: history.span.map { Date(seconds: $0.lowerBound)...Date(seconds: $0.upperBound) },
                                      commitSpan: isLive ? nil : { span in
                                          history.span = span.lowerBound.timeIntervalSince1970...span.upperBound.timeIntervalSince1970
                                      },
                                      otherProcesses: { b in
                                          let named = Set(colors.keys)
                                          return isLive ? live.otherProcesses(bucket: b, named: named)
                                              : history.otherProcesses(bucket: b, named: named)
                                      },
                                      hover: hover)
                            // The pill's column: the plot, its y-axis labels, the event markers and the hover bubble stay left of it.
                            .padding(.trailing, ChartZoom.width)
                            .overlay(alignment: .trailing) { ChartZoom() }
                            .frame(height: 280)
                            .padding()
                            // Above the table, so an event bubble that reaches past the chart never draws under it.
                            .zIndex(1)
                        if let span = history.span, !isLive { spanBar(span) }
                    }
                    if isLive, let lostAt = live.lostAt { lostBar(lostAt) }
                    AppTable(ranking: shown, colors: colors, metric: history.metric, sparklines: isLive ? live.sparklines : history.sparklines,
                             shareTotal: group.map { _ in ranking.reduce(0) { $0 + $1.average } }, live: isLive, hover: hover)
                        .equatable()
                }
                // Live and a range are different charts: the identity makes Start and Pause Live cross-fade, not morph.
                .id(isLive)
                // The table scrolls under the footer, and its last row can scroll clear of it.
                .screenFooter(footer ? MetricFooter(metric: history.metric, live: isLive, stacked: points) : nil)
                .onGeometryChange(for: Bool.self) { $0.size.height >= 640 } action: { _tall.wrappedValue = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Without the chart the table scrolls under the range bar.
        .safeAreaBar(edge: .top, spacing: 0) { RangeBar() }
        // Start Live, Pause Live and a new range, metric or group fade from one chart to the next instead of a jump: the old
        // chart fades out as the new one fades in, and the marks never interpolate (`.id(isLive)` makes the two Live states
        // separate charts).
        .animation(Motion.fade(), value: isLive)
        .animation(Motion.fade(), value: isLive ? live.state : history.state)
        .screenTitle(title ?? "Apps", subtitle: subtitle(ranking, shown: shown),
                     icon: focus.map(TitleIcon.app) ?? group.map { .symbol($0.symbol, $0.color.color) } ?? .symbol("square.grid.2x2"))
        // A span hidden with the chart would rank the table for a time nobody sees.
        .onChange(of: chart, initial: true) { _, shown in if !shown { history.span = nil } }
    }

    /// The view filter, never the time range (the range bar shows it).
    private func subtitle(_ ranking: [AppRank], shown: [AppRank]) -> Text {
        if let focus { return Text("Pinned: \(AppName.display(focus, history: history))") }
        if !selection.search.isEmpty { return Text("\(shown.count) of ^[\(ranking.count) app](inflect: true)") }
        return group.map { _ in Text("Group · ^[\(ranking.count) app](inflect: true)") } ?? Text("All Apps")
    }

    private func hover(_ key: String, _ inside: Bool) {
        // Moving between two rows can report the new row before the old one's exit.
        if inside { _hovered.wrappedValue = key } else if _hovered.wrappedValue == key { _hovered.wrappedValue = nil }
    }

    private var collecting: some View {
        ContentUnavailableView("Collecting Data…", systemImage: "clock",
                               description: Text("The helper records every 5 s. The chart shows after the first records."))
    }


    private func spanBar(_ span: ClosedRange<Double>) -> some View {
        let interval = Date(seconds: span.lowerBound)..<Date(seconds: span.upperBound)
        return HStack {
            Text("Ranked for \(interval.formatted(history.range.intervalFormat))")
                .foregroundStyle(.secondary)
            // By the line it undoes, and named for its result (user call, SC1).
            Button("Show Whole Range") { history.span = nil }
                .keyboardShortcut(.cancelAction)
                .help("Clear the selected time span and rank for the whole range")
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.bottom, Layout.gap)
    }

    /// In the span bar's place while Live has lost the helper: the chart and table keep the last data.
    private func lostBar(_ lostAt: Double) -> some View {
        HStack {
            Label("Helper not reachable. Data as of \(Date(seconds: lostAt).formatted(date: .omitted, time: .shortened))",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Helper Settings") {
                settingsTab = "helper"
                // `openSettings` does not activate the app, so the window would open behind the frontmost app.
                NSApp.activate()
                openSettings()
            }
            .help("Open the helper settings")
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, Layout.gap)
    }
}
