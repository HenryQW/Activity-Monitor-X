import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; Range is set once per question, so it is a
/// button with a popover in the trailing group with the filter and the inspector. Search is the system toolbar field. Apps adds Show Chart. System
/// screens show no app data: their items are removed, not disabled; Disk keeps Range, Disk Map adds its target and Scan,
/// Hardware has Refresh. Calendar keeps Metric only: it has its own periods in place of Range.
struct MainToolbar: CustomizableToolbarContent {
    @Environment(AlertsModel.self) private var alerts
    let history: HistoryModel
    let selection: Selection
    let diskMap: DiskMapModel
    /// The window is too narrow for the Metric segments.
    let compact: Bool

    /// Alerts are not filtered by Metric, Range or Hide Quiet, so those items are removed there.
    private var filters: Bool { !selection.isSystem && selection.sidebar != .alerts }

    var body: some CustomizableToolbarContent {
        if filters || selection.sidebar == .calendar {
            ToolbarItem(id: "metric", placement: .principal) {
                // Segments while they fit, else a menu, so Metric never goes into the » overflow.
                if compact {
                    Menu {
                        metricPicker.pickerStyle(.inline)
                    } label: {
                        Text(history.metric.label)
                    }
                    .accessibilityLabel("Metric")
                    .accessibilityValue(history.metric.label)
                    .help("Choose the metric")
                } else {
                    metricPicker.pickerStyle(.segmented).help("Choose the metric")
                }
            }
        }
        if selection.sidebar == .alerts {
            ToolbarItem(id: "showDismissed", placement: .primaryAction) {
                Toggle("Show Dismissed", systemImage: alerts.showDismissed ? "eye" : "eye.slash", isOn: Bindable(alerts).showDismissed)
                    .help(alerts.showDismissed ? "Hide dismissed alerts" : "Show dismissed alerts")
            }
        }
        if filters || selection.sidebar == .disk {
            ToolbarItem(id: "live", placement: .primaryAction) {
                Toggle("Live", systemImage: "dot.radiowaves.left.and.right",
                       isOn: Binding(get: { history.range == .live }, set: { _ in history.toggleLive() }))
                    .labelStyle(.iconOnly)
                    .help(history.range == .live ? "Stop live data" : "Show live data")
            }
            range
        }
        if selection.sidebar == .diskMap {
            ToolbarItem(id: "diskMapTarget", placement: .primaryAction) { DiskMapTargetMenu(model: diskMap) }
            ToolbarItem(id: "diskMapScan", placement: .primaryAction) { DiskMapScanButton(model: diskMap) }
        }
        if selection.sidebar == .hardware {
            ToolbarItem(id: "refresh", placement: .primaryAction) {
                // ⌘R lives on the View menu command.
                Button("Refresh", systemImage: "arrow.clockwise") { selection.refreshes += 1 }
                    .help("Refresh the hardware information")
            }
        }
        if (selection.sidebar ?? .apps) == .apps {
            ToolbarItem(id: "showChart", placement: .primaryAction) {
                Toggle("Show Chart", systemImage: "chart.xyaxis.line", isOn: Bindable(selection).showChart)
                    .help(selection.showChart ? "Hide the chart" : "Show the chart")
            }
        }
        if filters {
            ToolbarItem(id: "hideQuiet", placement: .primaryAction) {
                Toggle("Hide Quiet System Processes", systemImage: "moon.zzz", isOn: Bindable(history).hideQuietSystem)
                    // A group shows all its members.
                    .disabled(history.scope != nil)
                    .help(history.hideQuietSystem ? "Show quiet system processes" : "Hide quiet system processes")
            }
        }
        if !selection.isSystem {
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                // ⌥⌘I lives on the View menu command.
                Button("Inspector", systemImage: "sidebar.trailing") { selection.inspectorShown.toggle() }
                    .help(selection.inspectorShown ? "Hide the inspector" : "Show the inspector")
            }
            // Last, where the search field opens; the field replaces it (`ToolbarSearch` in MainWindow).
            if !selection.searchPresented && selection.query.isEmpty {
                ToolbarItem(id: "search", placement: .primaryAction) {
                    Button("Search", systemImage: "magnifyingglass") { selection.searchPresented = true }
                        .help("Search apps, processes and PIDs")
                }
            }
        }
    }

    private var metricPicker: some View {
        Picker("Metric", selection: Bindable(history).metric) {
            ForEach(history.metrics, id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
    }

    private var range: some CustomizableToolbarContent {
        ToolbarItem(id: "range", placement: .primaryAction) {
            // The title names the range or the custom window: a toolbar button shows no value of its own.
            Button { selection.rangeShown = true } label: {
                Label(rangeTitle, systemImage: "clock")
            }
            .labelStyle(.titleOnly)
            .help("Choose the time range")
            .accessibilityLabel("Range")
            .accessibilityValue(history.custom.map { "From \(text($0.lowerBound)) to \(text($0.upperBound))" } ?? history.range.spoken)
            .popover(isPresented: Bindable(selection).rangeShown, arrowEdge: .bottom) {
                RangePopover(history: history) { selection.rangeShown = false }
            }
        }
    }

    /// The range's label, or the custom window: only its end while the window is narrow.
    private var rangeTitle: String {
        guard let custom = history.custom else { return history.range.label }
        return compact ? "To \(text(custom.upperBound))" : "\(text(custom.lowerBound)) to \(text(custom.upperBound))"
    }

    private func text(_ seconds: Double) -> String {
        Date(timeIntervalSince1970: seconds).formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

/// Custom Range on the left, the quick ranges on the right. Apply or a quick range closes it.
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
        HStack(alignment: .top, spacing: 16) {
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
            Divider()
            // A click applies the range; a custom window has none checked.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(HistoryRange.allCases, id: \.self) { range in
                    if range == .hour || range == .week { Divider() }
                    row(range)
                }
            }
            .fixedSize()
        }
        .padding()
    }

    private func row(_ range: HistoryRange) -> some View {
        let current = history.custom == nil && history.range == range
        return Button {
            history.range = range
            close()
        } label: {
            HStack {
                Text(range == .live ? "Live" : range == .hour ? "Last hour" : "Last \(range.spoken)")
                Spacer(minLength: 16)
                Image(systemName: "checkmark").opacity(current ? 1 : 0).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
        .help(range == .live ? "Show live data" : "Show the last \(range.spoken)")
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
