import AMXCore
import SwiftUI

/// The time range above the content of the screens that have one (Apps, pinned apps, groups, Disk): the quick ranges as
/// segments, then the window shown and Custom…, which opens the From/To pickers. Live is a segment: choosing it starts
/// Live, and choosing it again pauses back to the range before it (D48). A custom window checks no segment. Where the bar
/// is narrow, the window text goes first, then the segments become a pop-up.
struct RangeBar: View {
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection

    /// Narrower than the segments and Custom… need (measured): the ranges become a pop-up.
    private let _narrow = State(initialValue: false)

    var body: some View {
        HStack {
            if _narrow.wrappedValue {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
            Spacer(minLength: 12)
            // The whole text or none.
            ViewThatFits(in: .horizontal) {
                Text(window).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            Button("Custom…") { selection.rangeShown = true }
                .fixedSize()
                .help("Choose a custom time range")
                .popover(isPresented: Bindable(selection).rangeShown, arrowEdge: .bottom) {
                    RangePopover(history: history) { selection.rangeShown = false }
                }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onGeometryChange(for: Bool.self) { $0.size.width < 460 } action: { _narrow.wrappedValue = $0 }
    }

    private var picker: some View {
        Picker("Range", selection: Binding<HistoryRange?>(
            get: { history.custom == nil ? history.range : nil },
            set: { range in
                guard let range else { return }
                if range == .live { history.toggleLive() } else { history.range = range }
            })) {
            ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).accessibilityLabel($0.spoken).tag(HistoryRange?.some($0)) }
        }
        .labelsHidden()
        .fixedSize()
        .help(history.range == .live ? "Choose a range, or Live again to pause live data" : "Choose the time range")
    }

    /// The custom window, or the loaded one: it starts later than the range where recording began inside it.
    private var window: String {
        if history.range == .live { return "Live, updated each second" }
        let window = history.custom ?? history.start...history.end
        return "\(text(window.lowerBound)) to \(text(window.upperBound))"
    }

    private func text(_ seconds: Double) -> String {
        Date(timeIntervalSince1970: seconds).formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

/// From and To, from the oldest history kept to now; Apply shows the window and closes it.
private struct RangePopover: View {
    let history: HistoryModel
    let close: () -> Void
    /// From the oldest history kept (the hour tier) to now.
    private let bounds: ClosedRange<Date>
    private let _from: State<Date>
    private let _to: State<Date>

    init(history: HistoryModel, close: @escaping () -> Void) {
        (self.history, self.close) = (history, close)
        let now = Date().timeIntervalSince1970
        bounds = Date(timeIntervalSince1970: now - RetentionPolicy().hour)...Date(timeIntervalSince1970: now)
        let window = history.custom ?? (now - history.range.seconds)...now
        _from = State(initialValue: Date(timeIntervalSince1970: window.lowerBound))
        _to = State(initialValue: Date(timeIntervalSince1970: window.upperBound))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Range").font(.headline)
            Form {
                DatePicker("From", selection: _from.projectedValue, in: bounds)
                    .help("Choose the start of the range")
                DatePicker("To", selection: _to.projectedValue, in: bounds)
                    .help("Choose the end of the range")
            }
            Button("Apply") {
                history.show(from: _from.wrappedValue.timeIntervalSince1970, to: _to.wrappedValue.timeIntervalSince1970)
                close()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(_from.wrappedValue >= _to.wrappedValue)
            .help("Show the custom range")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
    }
}

private extension HistoryRange {
    /// For VoiceOver: "24H" is read as letters.
    var spoken: String {
        switch self {
        case .live: "Live"
        case .hour: "1 hour"
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }
}
