@testable import AMXCore
import Foundation
import Testing

@Suite struct LiveSnapshotTests {
    @Test func snapshotRoundTripsJSON() throws {
        let snapshot = LiveSnapshot(
            ts: 1_700_000_000.5,
            system: LiveSystem(cpu: 12.5, memUsed: 8 << 30, pressureLevel: 2, thermalState: 1),
            processes: [LiveProcess(pid: 42, startTime: 1_699_999_000.25, name: "Safari Helper",
                                    appKey: "/Applications/Safari.app", appName: "Safari",
                                    path: "/Applications/Safari.app/Contents/MacOS/Safari", cpu: 150.5, mem: 1 << 28,
                                    diskR: 1024, diskW: 2048, netIn: 300, netOut: 400, gpu: 7.5, energy: 15.25)])
        let decoded = try JSONDecoder().decode(LiveSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func liveScore() {
        let p = LiveProcess(pid: 7, startTime: 1, name: "p", appKey: "p", appName: "p", path: nil, cpu: 200,
                            mem: 8_589_934_592, diskR: 0, diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: 0)
        let snap = LiveSnapshot(ts: 0, system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 0, thermalState: 0), processes: [p])
        let device = Device(cores: 10, memory: 17_179_869_184)
        #expect(liveTracks([snap], metric: .score, device: device)[0].slices[0].value == 35)
    }

    @Test func liveTopSumsPerApp() {
        func p(_ pid: Int32, _ app: String, cpu: Double, mem: UInt64) -> LiveProcess {
            LiveProcess(pid: pid, startTime: 1, name: "p\(pid)", appKey: "/\(app).app", appName: app, path: nil, cpu: cpu,
                        mem: mem, diskR: 0, diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: 0)
        }
        let snap = LiveSnapshot(ts: 0, system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 1, thermalState: 0),
                                processes: [p(1, "A", cpu: 10, mem: 100), p(2, "A", cpu: 30, mem: 50),
                                            p(3, "B", cpu: 25, mem: 500), p(4, "C", cpu: 0, mem: 1)])
        #expect(LiveTop.apps(snap, limit: 2) == [LiveTop.Row(app: AppKey(key: "/A.app", name: "A"), cpu: 40, mem: 150),
                                                  LiveTop.Row(app: AppKey(key: "/B.app", name: "B"), cpu: 25, mem: 500)])
    }

    @Test func liveDemandStopsAfterThreeSeconds() {
        var demand = LiveDemand()
        #expect(!demand.shouldSample(now: 0))
        demand.requested(at: 0)
        #expect(demand.shouldSample(now: 2.9))
        #expect(!demand.shouldSample(now: 3.1))
    }

    @Test func clientMapsConnectionErrorToUnreachable() async {
        let client = DaemonClient(machServiceName: "com.henryqw.activitymonitorx.nonexistent")
        let error = await #expect(throws: DaemonClientError.self) { try await client.live() }
        #expect(error.map { if case .unreachable = $0 { true } else { false } } == true)
    }
}

@Test func liveGapShowsNoValue() {
    func snap(_ ts: Double, cpu: Double) -> LiveSnapshot {
        LiveSnapshot(ts: ts, system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 0, thermalState: 0),
                     processes: [LiveProcess(pid: 7, startTime: 1, name: "p", appKey: "/A.app", appName: "A", path: "/usr/bin/p", cpu: cpu,
                                             mem: 0, diskR: 2, diskW: 3, netIn: 0, netOut: 0, gpu: 0, energy: 0)])
    }
    let snapshots = [snap(0, cpu: 10), snap(1, cpu: 20), snap(10, cpu: 30)]
    let track = liveTracks(snapshots, metric: .cpu)[0]
    // The snapshot before the 9 s gap holds 2 s, not until the next one.
    #expect(track.slices.map { [$0.start, $0.end, $0.value] } == [[0, 1, 10], [1, 3, 20], [10, 11, 30]])
    #expect(track.app == AppKey(key: "/A.app", name: "A"))
    #expect(liveTracks(snapshots, metric: .disk)[0].slices[0].value == 5)
}

/// Live tracks of `snapshots` (ordered by ts), appended one at a time.
func liveTracks(_ snapshots: [LiveSnapshot], metric: Metric, device: Device = .current) -> [ProcessTrack] {
    var live = LiveTracks(metric: metric, device: device)
    for snapshot in snapshots { live.append(snapshot) }
    return live.tracks
}

/// One snapshot at a time, trimmed to 5 min, with a backfill and a metric change, gives after every snapshot the same
/// chart and table as the full build from all snapshots so far, less the slices that end by the window's start (Live's
/// build before it went incremental trimmed by snapshot time instead, and so dropped a snapshot whose 2 s hold after a
/// gap still reached into the window).
@Test func incrementalLiveTracksEqualTheFullBuild() {
    func proc(_ pid: Int32, start: Double = 1, app: String, cpu: Double, mem: UInt64) -> LiveProcess {
        LiveProcess(pid: pid, startTime: start, name: "p\(pid)", appKey: "/\(app).app", appName: app, path: nil, cpu: cpu,
                    mem: mem, diskR: 0, diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: 0)
    }
    // Two 4 s gaps; the window's left edge passes the first one.
    let offsets = (0...402).filter { !(40...42).contains($0) && !(160...162).contains($0) }
    let snapshots = offsets.map { k in
        var ps = [proc(1, app: "A", cpu: Double(k % 7) * 10, mem: 1000), proc(2, app: "B", cpu: 0, mem: k < 200 ? 500 : 600)]
        if (50..<120).contains(k) { ps.append(proc(3, app: "C", cpu: 5, mem: 10)) }
        if k >= 300 { ps.append(proc(3, start: 2, app: "C", cpu: 2, mem: 20)) }  // the pid is reused
        if k >= 350 { ps.append(proc(4, app: "D", cpu: 30, mem: 30)) }
        if k < 10 || (20..<30).contains(k) { ps.append(proc(6, app: "E", cpu: 1, mem: 40)) }
        if (20..<45).contains(k) { ps.append(proc(9, app: "R9", cpu: 4, mem: 50)) }  // first seen in the raw history
        return LiveSnapshot(ts: 1000 + Double(k), system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 0, thermalState: 0), processes: ps)
    }
    func raw(_ metric: Metric) -> [ProcessTrack] {
        let scale = metric == .cpu ? 1.0 : 100
        func t(_ pid: Int32, _ slices: [(Double, Double, Double)]) -> ProcessTrack {
            ProcessTrack(processID: Int64(pid), pid: pid, startTime: 1, name: "p\(pid)", app: AppKey(key: "/R\(pid).app", name: "R"),
                         lastSeen: slices.last!.1, slices: slices.map { Slice(start: $0.0, end: $0.1, value: $0.2 * scale) })
        }
        return [t(1, [(900, 950, 3), (950, 1000, 4)]), t(9, [(960, 990, 8)]), t(8, [(800, 850, 1)])]
    }
    func full(_ kept: [LiveSnapshot], metric: Metric, from: Double) -> [ProcessTrack] {
        var slices: [ProcessIdentity: [Slice]] = [:]
        var latest: [ProcessIdentity: (p: LiveProcess, ts: Double)] = [:]
        for (i, s) in kept.enumerated() {
            let end = i + 1 < kept.count ? min(kept[i + 1].ts, s.ts + 2) : s.ts + 1
            for p in s.processes {
                let key = ProcessIdentity(pid: p.pid, startTime: p.startTime)
                slices[key, default: []].append(Slice(start: s.ts, end: end, value: metric == .cpu ? p.cpu : Double(p.mem)))
                latest[key] = (p, s.ts)
            }
        }
        var earlier: [ProcessIdentity: ProcessTrack] = [:]
        for var t in raw(metric) {
            t.slices.removeAll { $0.end <= from }
            if !t.slices.isEmpty { earlier[ProcessIdentity(pid: t.pid, startTime: t.startTime)] = t }
        }
        let live = latest.map { key, last in
            ProcessTrack(processID: 0, pid: last.p.pid, startTime: last.p.startTime, name: last.p.name,
                         app: AppKey(key: last.p.appKey, name: last.p.appName), lastSeen: last.ts,
                         slices: (earlier.removeValue(forKey: key)?.slices ?? []) + slices[key]!.filter { $0.end > from })
        }
        return live.filter { !$0.slices.isEmpty } + earlier.values
    }
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(1, abs(a), abs(b)) }
    func expectSame(_ got: [ProcessTrack], _ want: [ProcessTrack], last: Double) {
        let (from, to) = (last + 1 - 300, last + 1)
        let (a, b) = (AppSeries.stacked(got, from: from, to: to, bucket: 1), AppSeries.stacked(want, from: from, to: to, bucket: 1))
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.bucket == $1.bucket && $0.app == $1.app && close($0.value, $1.value) })
        let start = AppSeries.recordedStart(want, from: from)
        #expect(AppSeries.recordedStart(got, from: from) == start)
        let (ra, rb) = (AppSeries.ranking(got, from: start, to: to, bucket: 1, exitedBefore: last),
                        AppSeries.ranking(want, from: start, to: to, bucket: 1, exitedBefore: last))
        #expect(ra.map(\.app) == rb.map(\.app))
        #expect(zip(ra, rb).allSatisfy { x, y in
            close(x.average, y.average) && close(x.peak, y.peak) && x.processes.count == y.processes.count
                && zip(x.processes, y.processes).allSatisfy {
                    ($0.pid, $0.startTime, $0.lastSeen, $0.exited) == ($1.pid, $1.startTime, $1.lastSeen, $1.exited)
                        && close($0.average, $1.average) && close($0.peak, $1.peak)
                }
        })
    }

    var live = LiveTracks(metric: .cpu)
    var metric = Metric.cpu
    for (i, s) in snapshots.enumerated() {
        let from = s.ts + 1 - 300
        live.append(s)
        live.trim(before: from)
        if i == 0 { live.reset(metric: .cpu, raw: raw(.cpu), from: from) }
        if s.ts == 1200 {
            metric = .memory
            live.reset(metric: .memory, raw: raw(.memory), from: from)
        }
        expectSame(live.tracks, full(Array(snapshots[...i]), metric: metric, from: from), last: s.ts)
    }
    // Equal values share a slice: p2's memory is 500 until the gap, 500 after it, then 600.
    #expect(live.tracks.first { $0.pid == 2 }!.slices.count == 3)
}
