import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; the range is in `RangeBar` above the
/// content. Search is the system toolbar field. Capsules: Metric; Live; one action group of Quit, Info, More and Search.
/// Info and Search are on every screen. More holds the view toggles: Show Chart on Apps, Hide Quiet where Metric filters,
/// Show Dismissed on Alerts. System screens show no app data: their other items are removed, not disabled; on Disk the
/// Activity | Space segments take Metric's place and Space adds its target and Scan; Hardware has Refresh. Calendar keeps
/// Metric only: it has its own periods in place of a range.
struct MainToolbar: CustomizableToolbarContent {
    @Environment(AlertsModel.self) private var alerts
    let history: HistoryModel
    let selection: Selection
    let diskMap: DiskMapModel
    /// The window is too narrow for the Metric segments.
    let compact: Bool
    /// Where the items that can crowd the Metric segments report their width.
    let fit: ToolbarFit

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
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { if abs((fit.drawn[history.metrics.count] ?? 0) - $0) >= 1 { fit.drawn[history.metrics.count] = $0 } }
                }
            }
        }
        else if selection.sidebar == .disk {
            ToolbarItem(id: "diskPane", placement: .principal) { DiskPanePicker() }
        }
        else {
            // Without Metric and the system title, the action items would follow the title pill: the spacer keeps them at
            // the trailing edge.
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        if selection.sidebar == .alerts {
            ToolbarItem(id: "dismissAll", placement: .primaryAction) {
                // No confirmation: Show Dismissed and Restore bring the alerts back.
                let ids = alerts.undismissed(search: selection.search)
                // Destructive in the system's way: red words with the destructive role, and the margin of a word button.
                Button(role: .destructive) { alerts.dismiss(ids) } label: { Text("Dismiss All").padding(.horizontal, 6) }
                    .foregroundStyle(.red)
                    .disabled(ids.isEmpty)
                    .help("Dismiss all alerts shown. Show Dismissed lists them again.")
                    .accessibilityLabel("Dismiss all alerts shown")
            }
        }
        // Live is the screen's primary action: its own round capsule before the others.
        if selection.hasRange {
            ToolbarItem(id: "live", placement: .primaryAction) { LiveButton(history: history).fitItem("live", fit) }
            ToolbarSpacer(.fixed, placement: .primaryAction)
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
        // One compact capsule of icon buttons (TB1): Quit, Info, More and Search share a system control group, in the
        // order of use; Live keeps its own round capsule before it.
        ToolbarItem(id: "actions", placement: .primaryAction) {
            let quit = !selection.isSystem || selection.sidebar == .energy
            let more = filters || selection.sidebar == .alerts
            let search = !selection.searchPresented && selection.query.isEmpty
            ControlGroup {
                // The screens whose inspector is the app's, with its Quit; Force Quit stays there and in the confirmation.
                if quit {
                    let request = selection.app.flatMap(selection.quitRequest(of:))
                    let name = selection.signallable?.name ?? selection.app?.name
                    let help = selection.process == nil ? "Quit \(name ?? "the selected app") and close its windows"
                        : "Ask \(name ?? "the selected process") to quit"
                    Button("Quit", systemImage: "xmark.circle") { selection.signalRequest = request }
                        .disabled(request == nil)
                        .help(help)
                        .accessibilityLabel(help)
                }
                // ⌥⌘I lives on the View menu command.
                Button("Info", systemImage: "info.circle") { selection.inspectorShown.toggle() }
                    .help(selection.inspectorShown ? "Hide the inspector pane" : "Show details of the selection in the inspector")
                    .accessibilityLabel(selection.inspectorShown ? "Hide the inspector pane" : "Show details of the selection in the inspector")
                if more {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Group {
                            if (selection.sidebar ?? .apps) == .apps {
                                Toggle("Show Chart", systemImage: "chart.xyaxis.line", isOn: Bindable(selection).showChart)
                            }
                            if filters {
                                Toggle("Hide Quiet System Processes", systemImage: "eye.slash", isOn: Bindable(history).hideQuietSystem)
                                    // A group shows all its members.
                                    .disabled(history.scope != nil)
                            }
                            if selection.sidebar == .alerts {
                                Toggle("Show Dismissed Alerts", systemImage: "eye", isOn: Bindable(alerts).showDismissed)
                            }
                        }
                            .labelStyle(.titleAndIcon)
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("More")
                    .help("Choose what the list and chart show")
                }
                // Last, where the search field opens; the field replaces it (`ToolbarSearch` in MainWindow).
                if search {
                    Button("Search", systemImage: "magnifyingglass") { selection.searchPresented = true }
                        .help("Search: \(selection.searchPrompt)")
                }
            }
            .controlGroupStyle(.navigation)
            .labelStyle(.iconOnly)
            // A new group when its buttons change: the toolbar kept the old capsule width (cramped icons until a resize).
            .id([quit, more, search])
            .fitItem("actions", fit)
        }
    }

    private var metricPicker: some View { MetricPicker(history: history) }
}

/// The round Live button: it starts Live, and pauses back to the range before it (D48). One button for both states, so
/// the focus stays. While Live runs it is prominent, tinted by the accent, never a status colour.
private struct LiveButton: View {
    let history: HistoryModel

    var body: some View {
        let on = history.range == .live
        let back = history.beforeLive.custom == nil ? "the \(history.beforeLive.range.spoken) range" : "the custom range"
        let hint = on ? "Pause Live and return to \(back)" : "Start Live data: the chart updates every second"
        Button("Live", systemImage: on ? "pause.fill" : "play.fill") { history.toggleLive() }
            .labelStyle(.iconOnly)
            .glassEffect(on ? .regular.tint(.accentColor) : .identity, in: .circle)
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityHint(hint)
            .help(hint)
    }
}

/// The Metric choice; `MainWindow` also lays out the segmented one off screen to measure its ideal width.
struct MetricPicker: View {
    let history: HistoryModel

    var body: some View {
        Picker("Metric", selection: Bindable(history).metric) {
            ForEach(history.metrics, id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
    }
}
