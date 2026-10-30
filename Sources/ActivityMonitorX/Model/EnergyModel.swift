import AMXCore
import Foundation
import Observation

/// The Energy screen's power and app shares, read once a second while the screen shows (`run`).
@Observable @MainActor
final class EnergyModel {
    struct Point {
        let date: Date
        /// Nil where the Mac did not report its power.
        let watts: Double?
    }

    private(set) var power: PowerReading?
    /// The live snapshot's processes, for `EnergyShare.top`; nil while amxd gives no live snapshot.
    private(set) var processes: [LiveProcess]?
    /// System power over the last 5 min of this visit.
    private(set) var points: [Point] = []
    /// The app shown with its processes, for this visit.
    var expanded: AppKey?
    /// Apps that always have their own band while they run, by app key (`EnergyShare.top`).
    var kept = Set(UserDefaults.standard.stringArray(forKey: "energyKeptApps") ?? []) {
        didSet { UserDefaults.standard.set(kept.sorted(), forKey: "energyKeptApps") }
    }
    /// The app order: by name, else by watts.
    var sortsByName = UserDefaults.standard.bool(forKey: "energySortsByName") {
        didSet { UserDefaults.standard.set(sortsByName, forKey: "energySortsByName") }
    }

    /// The screen's `.task`: ends, and so stops reading, when the screen goes. Per-app energy comes from amxd's live
    /// snapshot, which the Apps screen's poll does not fetch while a System screen shows.
    func run(client: DaemonClient) async {
        // App-wide (the inspector reads it), but each visit starts fresh.
        (points, expanded, power, processes) = ([], nil, nil, nil)
        while !Task.isCancelled {
            if MainWindowRef.windowShown {
                let power = PowerReader.read()
                let snapshot = try? await client.live()
                let now = Date()
                self.power = power
                processes = snapshot?.processes
                points.append(Point(date: now, watts: power.systemWatts))
                points.removeAll { $0.date < now.addingTimeInterval(-300) }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
