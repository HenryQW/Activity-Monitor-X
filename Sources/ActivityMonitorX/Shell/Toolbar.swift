import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; Range is set once per question, so it is a
/// pop-up in the trailing group with the filter and the inspector. Search is in the sidebar. System screens show no app
/// data: their items are removed, not disabled; Disk keeps Range, Disk Map adds its target and Scan, Hardware has Refresh.
struct MainToolbar: CustomizableToolbarContent {
    let history: HistoryModel
    let selection: Selection
    let diskMap: DiskMapModel

    var body: some CustomizableToolbarContent {
        if !selection.isSystem {
            ToolbarItem(id: "metric", placement: .principal) {
                Picker("Metric", selection: Bindable(history).metric) {
                    ForEach(history.metrics, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        if !selection.isSystem || selection.sidebar == .disk {
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
            }
        }
        if !selection.isSystem {
            ToolbarItem(id: "hideQuiet", placement: .primaryAction) {
                Toggle("Hide Quiet System Processes", systemImage: "line.3.horizontal.decrease", isOn: Bindable(history).hideQuietSystem)
                    // A group shows all its members.
                    .disabled(history.scope != nil)
            }
            ToolbarItem(id: "inspector", placement: .primaryAction) {
                // ⌥⌘I lives on the View menu command.
                Button("Inspector", systemImage: "sidebar.trailing") { WindowFit.toggleInspector(selection, score: history.scope != nil) }
            }
        }
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
            .help("Range")
        }
    }
}
