import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; the range and Live are in `RangeBar` above the
/// content. Search is the system toolbar field. Three capsules: Metric; the action group, Quit and Info; More and Search.
/// Info and Search are on every screen. More holds the view toggles: Show Chart on Apps, Hide Quiet where Metric filters,
/// Show Dismissed on Alerts. System screens show no app data: their other items are removed, not disabled; Disk's Space pill
/// adds its target and Scan, Hardware has Refresh. Calendar keeps Metric only: it has its own periods in place of a range.
struct MainToolbar: CustomizableToolbarContent {
    @Environment(AlertsModel.self) private var alerts
    let history: HistoryModel
    let selection: Selection
    let diskMap: DiskMapModel
    /// The window is too narrow for the Metric segments.
    let compact: Bool

    /// Alerts are not filtered by Metric or Hide Quiet, so those items are removed there.
    private var filters: Bool { !selection.isSystem && selection.sidebar != .alerts }

    var body: some CustomizableToolbarContent {
        if filters || selection.sidebar == .calendar {
            ToolbarItem(id: "metric", placement: .principal) {
                // Segments while they fit, else a pop-up that names the metric, so Metric never goes into the » overflow.
                if compact {
                    // The toolbar shows labels icon-only, which leaves the pop-up blank: it names the metric instead.
                    metricPicker.pickerStyle(.menu).labelStyle(.titleOnly)
                        .accessibilityLabel("Metric")
                        .help("Choose the metric this screen shows")
                } else {
                    metricPicker.pickerStyle(.segmented).help("Choose the metric this screen shows")
                }
            }
        }
        if selection.sidebar == .alerts {
            ToolbarItem(id: "dismissAll", placement: .primaryAction) {
                // No confirmation: Show Dismissed and Restore bring the alerts back.
                let ids = alerts.undismissed(search: selection.search)
                Button("Dismiss All") { alerts.dismiss(ids) }
                    .disabled(ids.isEmpty)
                    .help("Dismiss all alerts shown. Show Dismissed lists them again.")
                    .accessibilityLabel("Dismiss all alerts shown")
            }
        }
        if selection.showsSpace {
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
        // The screen's own items get a capsule apart from the action group; on other screens a spacer only costs width.
        if [.alerts, .hardware].contains(selection.sidebar) || selection.showsSpace {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        // The screens whose inspector is the app's, with its Quit; Force Quit stays there and in the confirmation.
        if !selection.isSystem || selection.sidebar == .energy {
            ToolbarItem(id: "quit", placement: .primaryAction) {
                let request = selection.app.flatMap(selection.quitRequest(of:))
                let name = selection.signallable?.name ?? selection.app?.name
                let help = selection.process == nil ? "Quit \(name ?? "the selected app") and close its windows"
                    : "Ask \(name ?? "the selected process") to quit"
                Button("Quit", systemImage: "xmark.circle") { selection.signalRequest = request }
                    .disabled(request == nil)
                    .help(help)
                    .accessibilityLabel(help)
            }
        }
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            // ⌥⌘I lives on the View menu command.
            Button("Info", systemImage: "info.circle") { selection.inspectorShown.toggle() }
                .help(selection.inspectorShown ? "Hide the inspector pane" : "Show details of the selection in the inspector")
                .accessibilityLabel(selection.inspectorShown ? "Hide the inspector pane" : "Show details of the selection in the inspector")
        }
        if filters || selection.sidebar == .alerts {
            ToolbarItem(id: "more", placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if (selection.sidebar ?? .apps) == .apps {
                        Toggle("Show Chart", isOn: Bindable(selection).showChart)
                    }
                    if filters {
                        Toggle("Hide Quiet System Processes", isOn: Bindable(history).hideQuietSystem)
                            // A group shows all its members.
                            .disabled(history.scope != nil)
                    }
                    if selection.sidebar == .alerts {
                        Toggle("Show Dismissed Alerts", isOn: Bindable(alerts).showDismissed)
                    }
                }
                .accessibilityLabel("More")
                .help("Choose what the list and chart show")
            }
        }
        // Last, where the search field opens; the field replaces it (`ToolbarSearch` in MainWindow).
        if !selection.searchPresented && selection.query.isEmpty {
            ToolbarItem(id: "search", placement: .primaryAction) {
                Button("Search", systemImage: "magnifyingglass") { selection.searchPresented = true }
                    .help("Search: \(selection.searchPrompt)")
            }
        }
    }

    private var metricPicker: some View {
        Picker("Metric", selection: Bindable(history).metric) {
            ForEach(history.metrics, id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
    }
}
