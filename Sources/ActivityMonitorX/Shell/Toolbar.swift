import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; Range is set once per question, so it is a
/// pop-up in the trailing group with the filter and the inspector. Search is in the sidebar. Apps adds Show Chart. System
/// screens show no app data: their items are removed, not disabled; Disk keeps Range, Disk Map adds its target and Scan,
/// Hardware has Refresh.
struct MainToolbar: CustomizableToolbarContent {
    let history: HistoryModel
    let selection: Selection
    let diskMap: DiskMapModel
    /// The window is too narrow for the Metric segments.
    let compact: Bool

    /// Alerts are not filtered by Metric, Range or Hide Quiet, so those items are removed there.
    private var filters: Bool { !selection.isSystem && selection.sidebar != .alerts }

    var body: some CustomizableToolbarContent {
        if filters {
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
        if filters || selection.sidebar == .disk {
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
                Toggle("Hide Quiet System Processes", systemImage: "line.3.horizontal.decrease", isOn: Bindable(history).hideQuietSystem)
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
            // A menu-style Picker shows no value in the toolbar (icon-only label), so the menu's title names the range.
            Menu {
                Picker("Range", selection: Bindable(history).range) {
                    ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(history.range.label, systemImage: "clock")
            }
            .labelStyle(.titleOnly)
            .help("Choose the time range")
            .accessibilityLabel("Range")
            .accessibilityValue(history.range.spoken)
        }
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
