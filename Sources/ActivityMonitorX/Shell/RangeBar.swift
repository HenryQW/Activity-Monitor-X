import AMXCore
import SwiftUI

/// The time range at the top of the content of the screens that have one (Apps, pinned apps, groups, Disk): a level 2
/// glass capsule that fits its content, with the quick ranges as segments, then the window shown (short; the full window
/// is its hint) and Custom…, which opens the From/To pickers. The controls have no bezel or track on the glass (D71). Live is the round toolbar button (`LiveButton`); while it
/// runs the window text reads "Live" and no segment is checked. A custom window checks no segment. Where the column is
/// narrow, the window text goes first, then the segments become a pop-up.
struct RangeBar: View {
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection

    var body: some View {
        // The first form whose width fits the column.
        ViewThatFits(in: .horizontal) {
            capsule(segments: true, window: true)
            capsule(segments: true, window: false)
            capsule(segments: false, window: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.inset)
    }

    private func capsule(segments: Bool, window shown: Bool) -> some View {
        HStack(spacing: Layout.padding) {
            if segments {
                CapsuleChoice(title: "Range", values: quick, selection: range) {
                    Text($0.label).accessibilityLabel($0.spoken)
                }
                .help("Choose the time range")
            } else {
                picker
            }
            if shown {
                Text(window).foregroundStyle(.secondary).lineLimit(1)
                    .help(full)
                    .accessibilityLabel("Time range")
                    .accessibilityValue(full)
            }
            // Without a bezel, Custom… needs a line to read apart from the window text.
            Divider().padding(.vertical, Layout.padding)
            // The segments' style: the same inner margin, so the word does not sit on the capsule's edge.
            Button("Custom…") { selection.rangeShown = true }
                .buttonStyle(.accessoryBar)
                .help("Choose a custom time range")
                .popover(isPresented: Bindable(selection).rangeShown, arrowEdge: .bottom) {
                    RangePopover(history: history) { selection.rangeShown = false }
                }
        }
        .fixedSize()
        .floatingCapsule()
    }

    /// The quick ranges; Live is the toolbar button.
    private var quick: [HistoryRange] { HistoryRange.allCases.filter { $0 != .live } }

    /// Live and a custom window check no range.
    private var range: Binding<HistoryRange?> {
        Binding(get: { history.custom == nil && history.range != .live ? history.range : nil },
                set: { range in if let range { history.range = range } })
    }

    private var picker: some View {
        Picker("Range", selection: range) {
            ForEach(quick, id: \.self) { Text($0.label).accessibilityLabel($0.spoken).tag(HistoryRange?.some($0)) }
        }
        .labelsHidden()
        .fixedSize()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .help("Choose the time range")
    }

    /// The custom window, or the loaded one: it starts later than the range where recording began inside it.
    private var span: ClosedRange<Double> { history.custom ?? history.start...history.end }

    /// With a zone forced, the text names it: every screen shows which zone its times are in.
    private var zone: String { AppTime.forced.map { " " + ZoneLabel.abbreviation($0, at: Date()) } ?? "" }

    /// The full window, for the hint and the accessibility value.
    private var full: String {
        if history.range == .live { return "Live, updated each second" }
        func text(_ seconds: Double) -> String {
            Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(timeZone: AppTime.zone).day().month(.abbreviated).hour().minute())
        }
        return "\(text(span.lowerBound)) to \(text(span.upperBound))\(zone)"
    }

    /// The short window shown: "Since 8:50 PM" for a range ending now ("Since yesterday, 8:50 PM" past midnight, "Since 16 Oct"
    /// from 7D), else the custom window as an interval with the shared parts left out ("22 to 23 Oct", "8:50 to 11:50 PM").
    private var window: String {
        if history.range == .live { return "Live" }
        let start = Date(timeIntervalSince1970: span.lowerBound), end = Date(timeIntervalSince1970: span.upperBound)
        let calendar = AppTime.calendar
        let sameDay = calendar.isDate(start, inSameDayAs: end)
        let text: String
        if history.custom != nil {
            // The interval style joins with a thin-spaced en dash.
            var style = Date.IntervalFormatStyle(timeZone: AppTime.zone)
            // Inside one day the times alone say which day only for today.
            style = !sameDay ? style.day().month(.abbreviated) : calendar.isDateInToday(start) ? style.hour().minute()
                : style.day().month(.abbreviated).hour().minute()
            if !calendar.isDate(start, equalTo: end, toGranularity: .year) { style = style.year() }
            text = (start..<end).formatted(style).replacingOccurrences(of: "\u{2009}\u{2013}\u{2009}", with: " to ")
        } else if [.hour, .day].contains(history.range) && sameDay {
            text = "Since " + start.formatted(Date.FormatStyle(timeZone: AppTime.zone).hour().minute())
        } else if [.hour, .day].contains(history.range) && calendar.isDateInYesterday(start) {
            text = "Since yesterday, " + start.formatted(Date.FormatStyle(timeZone: AppTime.zone).hour().minute())
        } else {
            text = "Since " + start.formatted(Date.FormatStyle(timeZone: AppTime.zone).day().month(.abbreviated))
        }
        return text + zone
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

extension HistoryRange {
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
