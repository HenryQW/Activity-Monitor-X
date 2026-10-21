public enum LiveTracks {
    /// Process tracks from Live snapshots ordered by `ts`. Live rows have no DB id (processID 0).
    /// A snapshot holds until the next one but at most 2 s, so a gap (Live left and resumed, or a
    /// daemon stall) shows no value instead of the old one.
    public static func build(_ snapshots: [LiveSnapshot], metric: Metric) -> [ProcessTrack] {
        struct Key: Hashable { let pid: Int32, startTime: Double }
        var slices: [Key: [Slice]] = [:]
        var latest: [Key: (p: LiveProcess, ts: Double)] = [:]
        for (i, snapshot) in snapshots.enumerated() {
            let end = i + 1 < snapshots.count ? min(snapshots[i + 1].ts, snapshot.ts + 2) : snapshot.ts + 1
            for p in snapshot.processes {
                let key = Key(pid: p.pid, startTime: p.startTime)
                let v = value(p, metric)
                slices[key, default: []].append(Slice(start: snapshot.ts, end: end, value: v, peak: v))
                latest[key] = (p, snapshot.ts)
            }
        }
        return latest.map { key, last in
            let p = last.p
            return ProcessTrack(processID: 0, pid: p.pid, startTime: p.startTime, name: p.name,
                                app: AppKey(key: p.appKey, name: p.appName), path: p.path, lastSeen: last.ts,
                                slices: slices[key]!)
        }
    }

    private static func value(_ p: LiveProcess, _ metric: Metric) -> Double {
        switch metric {
        case .cpu: p.cpu
        case .memory: Double(p.mem)
        case .disk: p.diskR + p.diskW
        case .network: p.netIn + p.netOut
        case .energy: p.energy
        case .gpu: p.gpu
        }
    }

    /// `live` with the raw history before it, so Live opens with its full 5 min. `raw` ends where the first snapshot
    /// starts; slices ending by `from` are dropped. A process in both (same pid and start time) keeps one track, its
    /// raw slices first; a process only in `raw` exited before Live started.
    public static func backfilled(_ live: [ProcessTrack], raw: [ProcessTrack], from: Double) -> [ProcessTrack] {
        struct Key: Hashable { let pid: Int32, startTime: Double }
        var earlier: [Key: ProcessTrack] = [:]
        for track in raw {
            let slices = track.slices.filter { $0.end > from }
            guard !slices.isEmpty else { continue }
            earlier[Key(pid: track.pid, startTime: track.startTime)] = ProcessTrack(
                processID: track.processID, pid: track.pid, startTime: track.startTime, name: track.name, app: track.app,
                path: track.path, lastSeen: track.lastSeen, slices: slices)
        }
        let merged = live.map { track in
            guard let before = earlier.removeValue(forKey: Key(pid: track.pid, startTime: track.startTime)) else { return track }
            return ProcessTrack(processID: track.processID, pid: track.pid, startTime: track.startTime, name: track.name,
                                app: track.app, path: track.path, lastSeen: track.lastSeen, slices: before.slices + track.slices)
        }
        return merged + earlier.values
    }
}
