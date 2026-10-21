public enum LiveTracks {
    /// Process tracks from Live snapshots ordered by `ts`. Live rows have no DB id (processID 0).
    /// A snapshot holds until the next one but at most 2 s, so a gap (Live left and resumed, or a
    /// daemon stall) shows no value instead of the old one.
    public static func build(_ snapshots: [LiveSnapshot], metric: Metric, device: Device = .current) -> [ProcessTrack] {
        var slices: [ProcessIdentity: [Slice]] = [:]
        var latest: [ProcessIdentity: (p: LiveProcess, ts: Double)] = [:]
        for (i, snapshot) in snapshots.enumerated() {
            let end = i + 1 < snapshots.count ? min(snapshots[i + 1].ts, snapshot.ts + 2) : snapshot.ts + 1
            for p in snapshot.processes {
                let key = ProcessIdentity(pid: p.pid, startTime: p.startTime)
                slices[key, default: []].append(Slice(start: snapshot.ts, end: end, value: value(p, metric, device)))
                latest[key] = (p, snapshot.ts)
            }
        }
        return latest.map { key, last in
            let p = last.p
            return ProcessTrack(processID: 0, pid: p.pid, startTime: p.startTime, name: p.name,
                                app: AppKey(key: p.appKey, name: p.appName), path: p.path, lastSeen: last.ts,
                                slices: slices[key]!, bundleID: p.bundleID, teamID: p.teamID)
        }
    }

    private static func value(_ p: LiveProcess, _ metric: Metric, _ device: Device) -> Double {
        switch metric {
        case .cpu: p.cpu
        case .memory: Double(p.mem)
        case .disk: p.diskR + p.diskW
        case .network: p.netIn + p.netOut
        case .energy: p.energy
        case .gpu: p.gpu
        case .score: device.score(cpu: p.cpu, mem: Double(p.mem))
        }
    }

    /// `live` with the raw history before it, so Live opens with its full 5 min. `raw` ends where the first snapshot
    /// starts; slices ending by `from` are dropped. A process in both (same pid and start time) keeps one track, its
    /// raw slices first; a process only in `raw` exited before Live started.
    public static func backfilled(_ live: [ProcessTrack], raw: [ProcessTrack], from: Double) -> [ProcessTrack] {
        var earlier: [ProcessIdentity: ProcessTrack] = [:]
        for var track in raw {
            track.slices.removeAll { $0.end <= from }
            if !track.slices.isEmpty { earlier[ProcessIdentity(pid: track.pid, startTime: track.startTime)] = track }
        }
        let merged = live.map { track in
            var track = track
            if let before = earlier.removeValue(forKey: ProcessIdentity(pid: track.pid, startTime: track.startTime)) {
                track.slices = before.slices + track.slices
            }
            return track
        }
        return merged + earlier.values
    }
}
