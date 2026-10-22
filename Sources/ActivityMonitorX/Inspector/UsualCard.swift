import AMXCore
import SwiftUI

/// The app's average and peak in the range (or span) against its usual value at the same hours of day in the 7 days
/// before the range.
struct UsualCard: View {
    @Environment(HistoryModel.self) private var history
    let rank: AppRank

    var body: some View {
        let metric = history.metric
        InspectorCard(title: "Compared to Usual") {
            if let usual = history.usual(of: rank.app) {
                Text(UsualProfile.describe(rank.average, usual: usual)).font(.title2)
                LabeledContent("Usual Average", value: metric.format(usual)).monospacedDigit()
                LabeledContent("Peak", value: UsualProfile.describe(rank.peak, usual: usual))
            } else {
                Text("Not enough history: this needs 2 days in the 7 days before the range.").foregroundStyle(.secondary)
            }
        }
        .help("The app's average and peak against its average at the same hours of day in the 7 days before the range.")
    }
}
