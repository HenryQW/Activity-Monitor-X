import AMXCore
import SwiftUI

/// With `focus`, the Timeline of one pinned app: its single area and its processes.
struct TimelineView: View {
    let focus: AppKey?
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live

    var body: some View {
        let isLive = history.range == .live
        let points = focus.map { isLive ? live.series(of: $0) : history.series(of: $0) }
            ?? (isLive ? live.stacked : history.stacked)
        let ranking = focus.map { app in (isLive ? live.rank(of: app) : history.rank(of: app)).map { [$0] } ?? [] }
            ?? (isLive ? live.ranking : history.ranking)
        let colors = AppPalette.colors(for: points)
        Group {
            switch isLive ? live.state : history.state {
            case .loading:
                ProgressView()
            case .empty:
                collecting
            case .failed(let message):
                ContentUnavailableView("Cannot Load Data", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready where points.isEmpty:
                if let focus {
                    ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line",
                                           description: Text("\(focus.name) has no data in this range."))
                } else {
                    collecting
                }
            case .ready:
                VStack(spacing: 0) {
                    TimelineChart(points: points, colors: colors, bucket: history.range.chartBucket, metric: history.metric,
                                  events: isLive ? [] : history.events,
                                  span: history.span.map { Self.date($0.lowerBound)...Self.date($0.upperBound) },
                                  commitSpan: isLive ? nil : { span in
                                      history.span = span.lowerBound.timeIntervalSince1970...span.upperBound.timeIntervalSince1970
                                  })
                        .frame(height: 280)
                        .padding()
                        .backgroundExtensionEffect()
                    if let span = history.span, !isLive { spanBar(span) }
                    AppTable(ranking: ranking, colors: colors, metric: history.metric)
                }
            }
        }
        .navigationTitle(focus?.name ?? "Timeline")
        .navigationSubtitle(history.range.subtitle)
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
