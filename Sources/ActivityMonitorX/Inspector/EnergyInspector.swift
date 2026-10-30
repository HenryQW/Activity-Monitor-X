import AMXCore
import SwiftUI

/// The Energy screen with no app selected (INS-4): power now and its source, then the apps that use the most, as the
/// diagram shows them.
struct EnergyInspector: View {
    @Environment(EnergyModel.self) private var model
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection

    var body: some View {
        let power = model.power
        let watts = power?.systemWatts
        let shares = (model.processes.map { EnergyShare.top($0, query: selection.search, kept: model.kept) } ?? []).filter { $0.app != nil }
        Form {
            CardSection("Power", summary: Text(watts.map { Units.watts($0) } ?? "No data")) {
                LabeledContent("Power source", value: power?.sourceText ?? "No data")
                if let battery = power?.battery { LabeledContent("Battery", value: battery.chargeText) }
            }
            .monospacedDigit()
            CardSection("Top Apps", summary: Text(shares.first.flatMap { top in top.app.map { "\($0.name), \(Units.percent(top.share * 100))" } } ?? "None"),
                        footer: Text("Click an app in the energy flow to see its details.")) {
                ForEach(shares, id: \.app) { share in
                    if let app = share.app {
                        LabeledContent {
                            Text(watts.map { Units.watts($0 * share.share) } ?? Units.percent(share.share * 100))
                        } label: {
                            Label {
                                Text(AppName.display(app, history: history))
                            } icon: {
                                Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
                            }
                        }
                    }
                }
            }
            .monospacedDigit()
        }
        .formStyle(.grouped)
    }
}
