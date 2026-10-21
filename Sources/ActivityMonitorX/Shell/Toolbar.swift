import AMXCore
import SwiftUI

/// Metric is flipped often, so it is the segmented control in the centre; Range is set once per question, so it is a
/// pop-up in the trailing group with the filter and the inspector (search follows them, from `.searchable`).
struct MainToolbar: CustomizableToolbarContent {
    let history: HistoryModel
    let selection: Selection

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "metric", placement: .principal) {
            Picker("Metric", selection: Bindable(history).metric) {
                ForEach(Metric.recorded, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
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
        ToolbarItem(id: "hideQuiet", placement: .primaryAction) {
            Toggle("Hide Quiet System Processes", systemImage: "line.3.horizontal.decrease", isOn: Bindable(history).hideQuietSystem)
        }
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            // ⌥⌘I lives on the View menu command.
            Button("Inspector", systemImage: "sidebar.trailing") { selection.inspectorShown.toggle() }
        }
    }
}
