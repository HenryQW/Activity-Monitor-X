public struct SeriesPoint: Sendable {
    public let bucket: Double
    public let app: AppKey?  // nil is "Other"
    public let value: Double
}

public struct ProcessRank: Sendable, Identifiable {
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

public struct AppRank: Sendable, Identifiable {
    public var id: String { app.key }
    public let app: AppKey
    public let average: Double
    public let peak: Double
    public let processes: [ProcessRank]
}

public enum AppSeries {
    /// The later of `from` and the earliest slice start: averages and the x domain then cover recorded time only,
    /// not the part of the range before recording began.
    public static func recordedStart(_ tracks: [ProcessTrack], from: Double) -> Double {
        max(from, tracks.compactMap { $0.slices.first?.start }.min() ?? from)
    }

    /// Each app's time-weighted mean in each bucket of [from, to); the last bucket may be shorter.
    private static func bucketed(_ tracks: [ProcessTrack], from: Double, to: Double, bucket: Double)
        -> (starts: [Double], perApp: [AppKey: [Double]]) {
        let starts = Array(stride(from: from, to: to, by: bucket))
        // One app lookup per track, not per slice: hashing the key per slice dominated the 24H stack.
        var slot: [AppKey: Int] = [:]
        var values: [[Double]] = []
        for track in tracks {
            var i = slot[track.app]
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
                        slot[track.app] = i
                        values.append(Array(repeating: 0, count: starts.count))
                    }
                    values[i!][b] += slice.value * overlap / width
                }
            }
        }
        return (starts, slot.mapValues { values[$0] })
    }

    /// Tracks at the indices in `otherOnly` never get a series of their own: their values add to Other.
    public static func stacked(_ tracks: [ProcessTrack], from: Double, to: Double, bucket: Double, top: Int = 5,
                               otherOnly: Set<Int> = []) -> [SeriesPoint] {
        let (starts, perApp) = bucketed(without(tracks, otherOnly), from: from, to: to, bucket: bucket)
        let forced = otherOnly.isEmpty ? [:] : bucketed(otherOnly.sorted().map { tracks[$0] }, from: from, to: to, bucket: bucket).perApp
        // Range average is the width-weighted mean of the bucket values.
        let widths = starts.map { min($0 + bucket, to) - $0 }
        let averages = perApp.mapValues { zip($0, widths).reduce(0) { $0 + $1.0 * $1.1 } / (to - from) }
        let ordered = perApp.keys.sorted { (averages[$0]!, $1.key) > (averages[$1]!, $0.key) }
        let named = Array(ordered.prefix(top))
        let rest = ordered.dropFirst(top)

        var points: [SeriesPoint] = []
        let other = starts.indices.map { b in
            rest.reduce(0) { $0 + perApp[$1]![b] } + forced.values.reduce(0) { $0 + $1[b] }
        }
        let otherTotal = zip(other, widths).reduce(0) { $0 + $1.0 * $1.1 }
        for (b, start) in starts.enumerated() {
            for app in named { points.append(SeriesPoint(bucket: start, app: app, value: perApp[app]![b])) }
            if otherTotal > 0 { points.append(SeriesPoint(bucket: start, app: nil, value: other[b])) }
        }
        return points
    }

    private static func without(_ tracks: [ProcessTrack], _ indices: Set<Int>) -> [ProcessTrack] {
        indices.isEmpty ? tracks : tracks.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
    }

    /// Every app's series in `count` equal buckets: one pass for all sparklines.
    public static func sparklines(_ tracks: [ProcessTrack], from: Double, to: Double, count: Int = 60,
                                  excluding: Set<Int> = []) -> [AppKey: [Double]] {
        let points = stacked(without(tracks, excluding), from: from, to: to, bucket: (to - from) / Double(count), top: .max)
        return Dictionary(grouping: points) { $0.app! }.mapValues { $0.map(\.value) }
    }

    /// An app's peak is its highest summed `bucket` value; a process's peak is its highest recorded value.
    /// A process is exited when its `lastSeen` is before `exitedBefore`: the latest Live snapshot's ts, or now − 70 s
    /// for history (`last_seen` reads as a minute's first tick).
    public static func ranking(_ allTracks: [ProcessTrack], from: Double, to: Double, bucket: Double,
                               excluding: Set<Int> = [], exitedBefore: Double = 0) -> [AppRank] {
        let tracks = without(allTracks, excluding)
        let perApp = bucketed(tracks, from: from, to: to, bucket: bucket).perApp
        var byApp: [AppKey: [ProcessRank]] = [:]
        for track in tracks {
            let inSpan = track.slices.filter { min($0.end, to) > max($0.start, from) }
            guard !inSpan.isEmpty else { continue }
            let area = inSpan.reduce(0) { $0 + $1.value * (min($1.end, to) - max($1.start, from)) }
            let peak = inSpan.map(\.peak).max()!
            byApp[track.app, default: []].append(ProcessRank(
                processID: track.processID, pid: track.pid, startTime: track.startTime, name: track.name,
                average: area / (to - from), peak: peak,
                lastSeen: track.lastSeen, exited: track.lastSeen < exitedBefore))
        }
        return byApp.map { app, procs in
            let sorted = procs.sorted { ($1.average, $0.pid) < ($0.average, $1.pid) }
            return AppRank(app: app, average: procs.reduce(0) { $0 + $1.average },
                           peak: perApp[app]!.max()!, processes: sorted)
        }.sorted { ($1.average, $0.app.key) < ($0.average, $1.app.key) }
    }
}
