/// Live process tracks, built one snapshot at a time. Live rows have no DB id (processID 0). A snapshot holds until the
/// next one but at most 2 s, so a gap (Live left and resumed, or a daemon stall) shows no value instead of the old one.
/// Equal adjacent values share one slice, so an idle process keeps one slice, not one per second. Each process also
/// keeps its values of every metric, merged the same way, so a metric change rebuilds the tracks without the snapshots.
public struct LiveTracks: Sendable {
    public private(set) var metric: Metric
    /// The ts of the first and of the latest snapshot; nil before the first.
    public private(set) var start: Double?
    public private(set) var latest: Double?
    private let device: Device
    private var entries: [Entry] = []
    private var index: [ProcessIdentity: Int] = [:]

    private struct Entry: Sendable {
        var track: ProcessTrack
        /// Live values of every metric; empty for a process known only from the raw history.
        var rows: [Row] = []
        /// The ts of the latest snapshot holding the process.
        var seen: Double?
    }

    private struct Row: Sendable {
        let start: Double
        var end: Double
        let values: Values
    }

    private struct Values: Equatable, Sendable {
        let cpu, mem, disk, network, energy, gpu: Double

        init(_ p: LiveProcess) {
            (cpu, mem, disk, network, energy, gpu) = (p.cpu, Double(p.mem), p.diskR + p.diskW, p.netIn + p.netOut, p.energy, p.gpu)
        }

        func value(_ metric: Metric, _ device: Device) -> Double {
            switch metric {
            case .cpu: cpu
            case .memory: mem
            case .disk: disk
            case .network: network
            case .energy: energy
            case .gpu: gpu
            case .score: device.score(cpu: cpu, mem: mem)
            }
        }
    }

    public init(metric: Metric, device: Device = .current) {
        (self.metric, self.device) = (metric, device)
    }

    public var tracks: [ProcessTrack] { entries.map(\.track) }

    /// Adds a snapshot newer than `latest`.
    public mutating func append(_ snapshot: LiveSnapshot) {
        let ts = snapshot.ts
        if let latest {
            // The previous snapshot holds until this one, at most 2 s.
            let end = min(ts, latest + 2)
            for i in entries.indices where entries[i].seen == latest {
                let last = entries[i].track.slices.removeLast()
                entries[i].track.slices.append(Slice(start: last.start, end: end, value: last.value))
                entries[i].rows[entries[i].rows.count - 1].end = end
            }
        }
        for p in snapshot.processes {
            let key = ProcessIdentity(pid: p.pid, startTime: p.startTime)
            let i = index[key] ?? entries.count
            if i == entries.count {
                index[key] = i
                entries.append(Entry(track: Self.track(p, ts: ts, slices: [])))
            }
            // The latest snapshot names the process. The slices are shared with the last build's tracks, so the first
            // change below copies them, once per append.
            entries[i].track = Self.track(p, ts: ts, slices: entries[i].track.slices)
            let values = Values(p)
            Self.add(&entries[i].track.slices, start: ts, end: ts + 1, value: values.value(metric, device))
            if let last = entries[i].rows.last, last.end == ts, last.values == values {
                entries[i].rows[entries[i].rows.count - 1].end = ts + 1
            } else {
                entries[i].rows.append(Row(start: ts, end: ts + 1, values: values))
            }
            entries[i].seen = ts
        }
        start = start ?? ts
        latest = ts
    }

    /// Drops the slices that end by `from`, and the processes left without any.
    public mutating func trim(before from: Double) {
        for i in entries.indices {
            let slices = entries[i].track.slices.firstIndex { $0.end > from } ?? entries[i].track.slices.count
            if slices > 0 { entries[i].track.slices.removeFirst(slices) }
            let rows = entries[i].rows.firstIndex { $0.end > from } ?? entries[i].rows.count
            if rows > 0 { entries[i].rows.removeFirst(rows) }
        }
        if entries.contains(where: \.track.slices.isEmpty) {
            entries.removeAll { $0.track.slices.isEmpty }
            reindex()
        }
    }

    /// Rebuilds the tracks for `metric` from the kept values, with `raw` (history up to the first snapshot) before them.
    /// Raw slices ending by `from` are dropped. A process in both keeps one track, its raw slices first; a process only
    /// in `raw` exited before Live started.
    public mutating func reset(metric: Metric, raw: [ProcessTrack], from: Double) {
        self.metric = metric
        var earlier: [ProcessIdentity: ProcessTrack] = [:]
        for var track in raw {
            track.slices.removeAll { $0.end <= from }
            if !track.slices.isEmpty { earlier[ProcessIdentity(pid: track.pid, startTime: track.startTime)] = track }
        }
        // Processes from an earlier reset's raw history.
        entries.removeAll { $0.rows.isEmpty }
        for i in entries.indices {
            var slices: [Slice] = []
            for row in entries[i].rows { Self.add(&slices, start: row.start, end: row.end, value: row.values.value(metric, device)) }
            let track = entries[i].track
            entries[i].track.slices = (earlier.removeValue(forKey: ProcessIdentity(pid: track.pid, startTime: track.startTime))?.slices ?? []) + slices
        }
        entries += earlier.values.map { Entry(track: $0) }
        reindex()
    }

    private mutating func reindex() {
        index = Dictionary(uniqueKeysWithValues: entries.enumerated().map {
            (ProcessIdentity(pid: $0.element.track.pid, startTime: $0.element.track.startTime), $0.offset)
        })
    }

    /// Extends the last slice when it ends at `start` with the same value, else adds a slice.
    private static func add(_ slices: inout [Slice], start: Double, end: Double, value: Double) {
        if let last = slices.last, last.end == start, last.value == value {
            slices[slices.count - 1] = Slice(start: last.start, end: end, value: value)
        } else {
            slices.append(Slice(start: start, end: end, value: value))
        }
    }

    private static func track(_ p: LiveProcess, ts: Double, slices: [Slice]) -> ProcessTrack {
        ProcessTrack(processID: 0, pid: p.pid, startTime: p.startTime, name: p.name,
                     app: AppKey(key: p.appKey, name: p.appName), path: p.path, lastSeen: ts,
                     slices: slices, bundleID: p.bundleID, teamID: p.teamID)
    }
}
