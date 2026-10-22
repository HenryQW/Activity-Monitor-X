public struct SeriesPoint: Sendable {
    public let bucket: Double
    public let app: AppKey?  // nil is "Other"
    public let value: Double
}

public struct ProcessRank: Sendable, Identifiable, Equatable {
    public var id: Int64 { processID }
    public let processID: Int64
    public let pid: Int32
    public let startTime: Double
    public let name: String
    public let average: Double
    public let peak: Double
    public let lastSeen: Double
    /// Gone at the time of the load: see `AppSeries.ranking(exitedBefore:)`.
    public let exited: Bool
}

public struct AppRank: Sendable, Identifiable, Equatable {
    public var id: String { app.key }
    public let app: AppKey
    public let average: Double
    public let peak: Double
    public let processes: [ProcessRank]

    /// The inspector's rows: processes of one name together, names in order of their first process, so 14 idle
    /// helpers of one name read as one row.
    public static func byName(_ processes: some Sequence<ProcessRank>) -> [[ProcessRank]] {
        var groups: [[ProcessRank]] = [], index: [String: Int] = [:]
        for p in processes {
            if let i = index[p.name] { groups[i].append(p) } else { index[p.name] = groups.count; groups.append([p]) }
        }
        return groups
    }
}

public enum AppSeries {
    /// The later of `from` and the earliest slice start: averages and the x domain then cover recorded time only,
    /// not the part of the range before recording began.
    public static func recordedStart(_ tracks: [ProcessTrack], from: Double) -> Double {
        max(from, tracks.compactMap { $0.slices.first?.start }.min() ?? from)
    }

    /// Each key's time-weighted mean in each bucket of [from, to); the last bucket may be shorter.
    private static func bucketed<Key: Hashable>(_ tracks: [ProcessTrack], from: Double, to: Double, bucket: Double,
                                                key: (Int, ProcessTrack) -> Key) -> (starts: [Double], perKey: [Key: [Double]]) {
        let starts = Array(stride(from: from, to: to, by: bucket))
        // One key lookup per track, not per slice: hashing the app key per slice dominated the 24H stack.
        var slot: [Key: Int] = [:]
        var values: [[Double]] = []
        for (t, track) in tracks.enumerated() {
            let k = key(t, track)
            var i = slot[k]
            for slice in track.slices {
                let lo = max(Int(((slice.start - from) / bucket).rounded(.down)), 0)
                let hi = min(Int(((slice.end - from) / bucket).rounded(.up)), starts.count)
                guard lo < hi else { continue }
                for b in lo..<hi {
                    let width = min(starts[b] + bucket, to) - starts[b]
                    let overlap = min(slice.end, starts[b] + bucket, to) - max(slice.start, starts[b])
                    guard overlap > 0 else { continue }
                    if i == nil {
                        i = values.count
                        slot[k] = i
                        values.append(Array(repeating: 0, count: starts.count))
                    }
                    values[i!][b] += slice.value * overlap / width
                }
            }
        }
        return (starts, slot.mapValues { values[$0] })
    }

    /// The `top` apps get a series each, in rank order (D18 as amended by R-UI3): by their value in each bucket weighted
    /// by how far the bucket's stack total rises above the median total, then by range average, then by key. A short
    /// spike then outweighs a steady load; on a flat range every weight is 0, so the order is the average's.
    /// Apps whose key is in `always` (a colour the user chose) get a series too, after the top ones.
    /// Tracks at the indices in `otherOnly` never get a series of their own: their values add to Other.
    public static func stacked(_ tracks: [ProcessTrack], from: Double, to: Double, bucket: Double, top: Int = 5,
                               always: Set<String> = [], otherOnly: Set<Int> = []) -> [SeriesPoint] {
        let (starts, perApp) = bucketed(without(tracks, otherOnly), from: from, to: to, bucket: bucket) { $1.app }
        let forced = otherOnly.isEmpty ? [:] : bucketed(otherOnly.sorted().map { tracks[$0] }, from: from, to: to, bucket: bucket) { $1.app }.perKey
        let widths = starts.map { min($0 + bucket, to) - $0 }
        let totals = starts.indices.map { b in
            perApp.values.reduce(0) { $0 + $1[b] } + forced.values.reduce(0) { $0 + $1[b] }
        }
        let median = percentile(totals, 0.5)
        let excess = totals.map { max(0, $0 - median) }
        // Sort keys once per app: (score, range average), where the average is the width-weighted mean of the buckets.
        let ordered = perApp.map { app, values in
            (app, zip(values, excess).reduce(0) { $0 + $1.0 * $1.1 }, zip(values, widths).reduce(0) { $0 + $1.0 * $1.1 } / (to - from))
        }.sorted { ($0.1, $0.2, $1.0.key) > ($1.1, $1.2, $0.0.key) }.map(\.0)
        let named = Array(ordered.prefix(top)) + ordered.dropFirst(top).filter { always.contains($0.key) }
        let rest = ordered.dropFirst(top).filter { !always.contains($0.key) }.map { perApp[$0]! }

        var points: [SeriesPoint] = []
        let other = starts.indices.map { b in
            rest.reduce(0) { $0 + $1[b] } + forced.values.reduce(0) { $0 + $1[b] }
        }
        let otherTotal = zip(other, widths).reduce(0) { $0 + $1.0 * $1.1 }
        for (b, start) in starts.enumerated() {
            for app in named { points.append(SeriesPoint(bucket: start, app: app, value: perApp[app]![b])) }
            if otherTotal > 0 { points.append(SeriesPoint(bucket: start, app: nil, value: other[b])) }
        }
        return points
    }

    /// The `p` quantile with linear interpolation between ranks (inclusive method); 0 for no values.
    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = p * Double(sorted.count - 1)
        let i = Int(rank)
        return i + 1 < sorted.count ? sorted[i] + (rank - Double(i)) * (sorted[i + 1] - sorted[i]) : sorted[i]
    }

    private static func without(_ tracks: [ProcessTrack], _ indices: Set<Int>) -> [ProcessTrack] {
        indices.isEmpty ? tracks : tracks.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
    }

    /// `points` plus a closing point at the end of the last bucket, so a chart draws the last (partial) bucket too.
    public static func closed(_ points: [SeriesPoint], bucket: Double) -> [SeriesPoint] {
        guard let last = points.last?.bucket else { return points }
        return points + points.filter { $0.bucket == last }.map { SeriesPoint(bucket: last + bucket, app: $0.app, value: $0.value) }
    }

    /// Chart labels in order: nil is "Other", which no app gets; a name already given gets " (n)", the lowest free n.
    public static func labels(_ names: [String?]) -> [String] {
        var given: Set<String> = ["Other"]
        return names.map { name in
            guard let name else { return "Other" }
            var (label, n) = (name, 1)
            while !given.insert(label).inserted {
                n += 1
                label = "\(name) (\(n))"
            }
            return label
        }
    }

    /// The hover bubble's rows for one bucket: apps by value, Other last, without the rows `hides` (they would read 0).
    public static func bubbleRows(_ points: [SeriesPoint], hides: (Double) -> Bool) -> [SeriesPoint] {
        points.filter { !hides($0.value) }.sorted {
            ($0.app == nil ? 1 : 0, $1.value, $0.app?.key ?? "") < ($1.app == nil ? 1 : 0, $0.value, $1.app?.key ?? "")
        }
    }

    /// The hover bubble's breakdown of Other in [from, to) (one chart bucket): its `count` largest processes by mean.
    /// Other holds every track outside the `named` apps, and the tracks at the indices in `otherOnly`, as in `stacked`.
    public static func otherProcesses(_ tracks: [ProcessTrack], named: Set<AppKey>, otherOnly: Set<Int> = [],
                                      from: Double, to: Double, count: Int = 3) -> [(name: String, value: Double)] {
        tracks.enumerated()
            .filter { otherOnly.contains($0.offset) || !named.contains($0.element.app) }
            .map { (name: $0.element.name, value: $0.element.average(from: from, to: to)) }
            .filter { $0.value > 0 }
            .sorted { ($1.value, $0.name) < ($0.value, $1.name) }
            .prefix(count).map { $0 }
    }

    /// Every app's series in `count` equal buckets: one pass for all sparklines.
    public static func sparklines(_ tracks: [ProcessTrack], from: Double, to: Double, count: Int = 60,
                                  excluding: Set<Int> = []) -> [AppKey: [Double]] {
        guard to > from else { return [:] }
        let points = stacked(without(tracks, excluding), from: from, to: to, bucket: (to - from) / Double(count), top: .max)
        return Dictionary(grouping: points) { $0.app! }.mapValues { $0.map(\.value) }
    }

    /// One peak definition: an app's or a process's peak is its highest `bucket` value, so a process never peaks
    /// above its app. A process is exited when its `lastSeen` is before `exitedBefore`: the latest Live snapshot's ts,
    /// or now − the exit slack for history (`last_seen` reads as a minute's first tick).
    public static func ranking(_ allTracks: [ProcessTrack], from: Double, to: Double, bucket: Double,
                               excluding: Set<Int> = [], exitedBefore: Double = 0) -> [AppRank] {
        let tracks = without(allTracks, excluding)
        let perTrack = bucketed(tracks, from: from, to: to, bucket: bucket) { i, _ in i }.perKey
        var byApp: [AppKey: [Int]] = [:]
        for i in perTrack.keys { byApp[tracks[i].app, default: []].append(i) }
        return byApp.map { app, indices in
            var buckets = perTrack[indices[0]]!
            for i in indices.dropFirst() { for (b, v) in perTrack[i]!.enumerated() { buckets[b] += v } }
            let procs = indices.map { i in
                let track = tracks[i]
                return ProcessRank(processID: track.processID, pid: track.pid, startTime: track.startTime, name: track.name,
                                   average: track.average(from: from, to: to), peak: perTrack[i]!.max()!,
                                   lastSeen: track.lastSeen, exited: track.lastSeen < exitedBefore)
            }
            // A reused pid ties on pid too: the start time keeps the order from depending on dictionary order.
            let sorted = procs.sorted { ($1.average, $0.pid, $0.startTime) < ($0.average, $1.pid, $1.startTime) }
            return AppRank(app: app, average: procs.reduce(0) { $0 + $1.average }, peak: buckets.max()!, processes: sorted)
        }.sorted { ($1.average, $0.app.key) < ($0.average, $1.app.key) }
    }
}
