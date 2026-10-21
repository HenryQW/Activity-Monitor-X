import AMXCore
import SwiftUI

struct MainToolbar: CustomizableToolbarContent {
    let history: HistoryModel
    let selection: Selection

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "range", placement: .principal) {
            Picker("Range", selection: Bindable(history).range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem(id: "metric", placement: .principal) {
            Picker("Metric", selection: Bindable(history).metric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem(id: "hideQuiet", placement: .primaryAction) {
            Toggle("Hide Quiet System Processes", systemImage: history.hideQuietSystem ? "eye.slash" : "eye",
                   isOn: Bindable(history).hideQuietSystem)
        }
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            // ⌥⌘I lives on the View menu command.
            Button("Inspector", systemImage: "sidebar.trailing") { selection.inspectorShown.toggle() }
        }
    }
}
