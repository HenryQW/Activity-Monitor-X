import AMXCore
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
    /// The app key under the pointer in the legend or the table ("" for Other): its band stays, the others dim.
    private let _hovered = State<String?>(initialValue: nil)

    var body: some View {
        let isLive = history.range == .live
        let points = focus.map { isLive ? live.series(of: $0) : history.series(of: $0) }
            ?? (isLive ? live.stacked : history.stacked)
        let ranking = focus.map { app in (isLive ? live.rank(of: app) : history.rank(of: app)).map { [$0] } ?? [] }
            ?? (isLive ? live.ranking : history.ranking)
        let shown = AppSearch.filter(ranking, query: selection.search)
        let colors = AppPalette.colors(for: points)
        let title = focus?.name ?? group?.name
        let chart = title != nil || selection.showChart
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
                    ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line",
                                           description: Text("\(title) has no data in this range."))
                } else {
                    collecting
                }
            case .ready:
                VStack(spacing: 0) {
                    if chart {
                        TimelineChart(points: points, colors: colors, bucket: history.range.chartBucket, live: isLive, metric: history.metric,
                                      events: isLive ? [] : history.events,
                                      // An app without a band of its own is in Other's.
                                      highlighted: _hovered.wrappedValue.map { key in [colors.keys.contains { $0.key == key } ? key : ""] }
                                          ?? (selection.search.isEmpty ? nil : Set(shown.map(\.app.key))),
                                      span: history.span.map { Self.date($0.lowerBound)...Self.date($0.upperBound) },
                                      commitSpan: isLive ? nil : { span in
                                          history.span = span.lowerBound.timeIntervalSince1970...span.upperBound.timeIntervalSince1970
                                      },
                                      otherProcesses: { b in
                                          let named = Set(colors.keys)
                                          return isLive ? live.otherProcesses(bucket: b, named: named)
                                              : history.otherProcesses(bucket: b, named: named)
                                      },
                                      hover: hover)
                            .frame(height: 280)
                            .padding()
                            // Above the table, so an event bubble that reaches past the chart never draws under it.
                            .zIndex(1)
                        if let span = history.span, !isLive { spanBar(span) }
                    }
                    AppTable(ranking: shown, colors: colors, metric: history.metric, sparklines: isLive ? live.sparklines : history.sparklines,
                             shareTotal: group.map { _ in ranking.reduce(0) { $0 + $1.average } }, live: isLive, hover: hover)
                        .equatable()
                }
            }
        }
        .navigationTitle(title ?? "Apps")
        .navigationSubtitle(selection.subtitle(history.subtitle, shown: shown.count, of: ranking.count))
        // A span hidden with the chart would rank the table for a time nobody sees.
        .onChange(of: chart, initial: true) { _, shown in if !shown { history.span = nil } }
    }

    private func hover(_ key: String, _ inside: Bool) {
        // Moving between two rows can report the new row before the old one's exit.
        if inside { _hovered.wrappedValue = key } else if _hovered.wrappedValue == key { _hovered.wrappedValue = nil }
    }

    private var collecting: some View {
        ContentUnavailableView("Collecting data…", systemImage: "clock")
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private func spanBar(_ span: ClosedRange<Double>) -> some View {
        let interval = Self.date(span.lowerBound)..<Self.date(span.upperBound)
        // From 24H up a span can cross midnight, so it names the day.
        let format: Date.IntervalFormatStyle = history.range.seconds >= 86_400
            ? .interval.month(.abbreviated).day().hour().minute() : .interval.hour().minute()
        return HStack {
            Text("Ranked for \(interval.formatted(format))")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear Selection", systemImage: "xmark.circle.fill") { history.span = nil }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
                .help("Clear the selected time span")
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
