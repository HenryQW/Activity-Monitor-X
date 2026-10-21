import AMXCore
import SwiftUI

/// With `focus`, the Timeline of one pinned app: its single area and its processes. With `group`, the history model
/// is scoped to the group's members, and the table shows each app's share of the group.
struct TimelineView: View {
    let focus: AppKey?
    var group: ProcessGroup? = nil
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    @Environment(Selection.self) private var selection

    var body: some View {
        let isLive = history.range == .live
        let points = focus.map { isLive ? live.series(of: $0) : history.series(of: $0) }
            ?? (isLive ? live.stacked : history.stacked)
        let ranking = focus.map { app in (isLive ? live.rank(of: app) : history.rank(of: app)).map { [$0] } ?? [] }
            ?? (isLive ? live.ranking : history.ranking)
        let shown = AppSearch.filter(ranking, query: selection.search)
        let colors = AppPalette.colors(for: points)
        let title = focus?.name ?? group?.name
        Group {
            switch isLive ? live.state : history.state {
            case .loading:
                ProgressView()
            case .empty:
                collecting
            case .failed(let message):
                ContentUnavailableView("Cannot Load Data", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready where points.isEmpty:
                if let title {
                    ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line",
                                           description: Text("\(title) has no data in this range."))
                } else {
                    collecting
                }
            case .ready:
                VStack(spacing: 0) {
                    TimelineChart(points: points, colors: colors, bucket: history.range.chartBucket, metric: history.metric,
                                  events: isLive ? [] : history.events,
                                  highlighted: selection.search.isEmpty ? nil : Set(shown.map(\.app.key)),
                                  span: history.span.map { Self.date($0.lowerBound)...Self.date($0.upperBound) },
                                  commitSpan: isLive ? nil : { span in
                                      history.span = span.lowerBound.timeIntervalSince1970...span.upperBound.timeIntervalSince1970
                                  })
                        .frame(height: 280)
                        .padding()
                        .backgroundExtensionEffect()
                    if let span = history.span, !isLive { spanBar(span) }
                    AppTable(ranking: shown, colors: colors, metric: history.metric,
                             shareTotal: group.map { _ in ranking.reduce(0) { $0 + $1.average } })
                }
            }
        }
        .navigationTitle(title ?? "Timeline")
        .navigationSubtitle(selection.search.isEmpty ? history.subtitle
                            : "\(shown.count) of \(ranking.count) apps")
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
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
