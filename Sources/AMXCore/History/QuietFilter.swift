/// "Hide Quiet System Processes": which tracks the app tables and the top-5 choice leave out.
public enum QuietFilter {
    public static func isSystem(path: String?) -> Bool {
        guard let path else { return false }
        if path.hasPrefix("/usr/local/") { return false }
        return ["/System/", "/usr/", "/bin/", "/sbin/"].contains { path.hasPrefix($0) }
    }

    /// Average below which a process is quiet, in the metric's unit.
    public static func threshold(_ metric: Metric) -> Double {
        switch metric {
        case .cpu, .energy, .gpu: 1
        case .score: 0.5 // Not reached today: score is shown only for a group, where the quiet filter is off.
        case .memory: 100_000_000
        case .disk, .network: 100_000
        }
    }

    /// Indices into `tracks` of system processes whose average over [from, to) is below the threshold.
    public static func hidden(_ tracks: [ProcessTrack], metric: Metric, from: Double, to: Double) -> Set<Int> {
        let limit = threshold(metric)
        var result = Set<Int>()
        for (i, track) in tracks.enumerated() where isSystem(path: track.path) {
            if track.average(from: from, to: to) < limit { result.insert(i) }
        }
        return result
    }
}
