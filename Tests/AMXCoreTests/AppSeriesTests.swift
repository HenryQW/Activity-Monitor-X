import Testing
@testable import AMXCore

private func track(_ id: Int64, _ app: String, _ slices: [(Double, Double, Double, Double)], name: String = "p") -> ProcessTrack {
    ProcessTrack(processID: id, pid: Int32(id), startTime: 0, name: name, app: AppKey(key: app, name: app),
                 slices: slices.map { Slice(start: $0.0, end: $0.1, value: $0.2, peak: $0.3) })
}

private func value(_ points: [SeriesPoint], _ bucket: Double, _ key: String?) -> Double? {
    points.first { $0.bucket == bucket && $0.app?.key == key }?.value
}

@Test func stackedSumsHelpersIntoApp() {
    let t = [track(1, "A", [(0, 10, 10, 10)]), track(2, "A", [(0, 10, 30, 30)])]
    let points = AppSeries.stacked(t, from: 0, to: 10, bucket: 10)
    #expect(points.count == 1)
    #expect(value(points, 0, "A") == 40)
}

@Test func topFiveAndOther() {
    let t = (0..<7).map { track(Int64($0), "app\($0)", [(0, 10, Double(70 - $0 * 10), 0)]) }
    let points = AppSeries.stacked(t, from: 0, to: 10, bucket: 10)
    #expect(points.count == 6)
    #expect(value(points, 0, "app0") == 70)
    #expect(value(points, 0, "app4") == 30)
    #expect(value(points, 0, "app5") == nil)
    #expect(points.first { $0.app == nil }?.value == 30)

    let five = AppSeries.stacked(Array(t.prefix(5)), from: 0, to: 10, bucket: 10)
    #expect(five.count == 5)
    #expect(five.allSatisfy { $0.app != nil })
}

@Test func partialOverlapIsTimeWeighted() {
    let t = [track(1, "A", [(0, 5, 60, 60)])]
    let points = AppSeries.stacked(t, from: 0, to: 10, bucket: 10)
    #expect(value(points, 0, "A") == 30)
}

@Test func partialLastBucketUsesItsOwnWidth() {
    let t = [track(1, "A", [(0, 15, 20, 20)])]
    let points = AppSeries.stacked(t, from: 0, to: 15, bucket: 10)
    #expect(value(points, 0, "A") == 20)
    #expect(value(points, 10, "A") == 20)
}

@Test func zeroPointsKeepStacksAligned() {
    let t = [track(1, "A", [(0, 10, 5, 5)]), track(2, "B", [(10, 20, 7, 7)])]
    let points = AppSeries.stacked(t, from: 0, to: 20, bucket: 10)
    #expect(points.count == 4)
    #expect(value(points, 10, "A") == 0)
    #expect(value(points, 0, "B") == 0)
}

/// Twelve tracks of random slices in [0, 100) over eight apps.
private func randomTracks() -> [ProcessTrack] {
    var seed: UInt64 = 42
    func rnd() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
    var tracks: [ProcessTrack] = []
    for id in 0..<12 {
        var slices: [(Double, Double, Double, Double)] = []
        var t = rnd() * 20
        while t < 100 {
            let end = t + 1 + rnd() * 15
            slices.append((t, min(end, 100), rnd() * 100, 100))
            t = end + rnd() * 5
        }
        tracks.append(track(Int64(id), "app\(id % 8)", slices))
    }
    return tracks
}

@Test func stackTotalEqualsSumOfTracks() {
    let tracks = randomTracks()
    let points = AppSeries.stacked(tracks, from: 0, to: 100, bucket: 7)
    var starts: [Double] = []
    var s = 0.0
    while s < 100 { starts.append(s); s += 7 }
    for start in starts {
        let end = min(start + 7, 100)
        var expected = 0.0
        for tr in tracks {
            for sl in tr.slices {
                expected += sl.value * max(0, min(sl.end, end) - max(sl.start, start)) / (end - start)
            }
        }
        let got = points.filter { $0.bucket == start }.reduce(0) { $0 + $1.value }
        #expect(abs(got - expected) < 1e-9)
    }
}

@Test func sparklinesCoverEveryApp() {
    let t = (0..<7).map { track(Int64($0), "app\($0)", [(0, 60, Double($0), 0)]) } + [track(7, "late", [(30, 60, 6, 0)])]
    let lines = AppSeries.sparklines(t, from: 0, to: 60, count: 6)
    #expect(lines.count == 8)
    #expect(lines[AppKey(key: "app6", name: "app6")] == Array(repeating: 6, count: 6))
    #expect(lines[AppKey(key: "late", name: "late")] == [0, 0, 0, 6, 6, 6])

    // One key with two names stays two series, as in `stacked`.
    let renamed = ProcessTrack(processID: 9, pid: 9, startTime: 0, name: "p", app: AppKey(key: "late", name: "Late 2"),
                               slices: [Slice(start: 0, end: 60, value: 1, peak: 1)])
    #expect(AppSeries.sparklines(t + [renamed], from: 0, to: 60, count: 6).count == 9)
}

@Test func sameNameDifferentPathStaySeparate() {
    let a = ProcessTrack(processID: 1, pid: 1, startTime: 0, name: "Helper", app: AppKey(key: "/A.app", name: "Helper"),
                         slices: [Slice(start: 0, end: 10, value: 10, peak: 10)])
    let b = ProcessTrack(processID: 2, pid: 2, startTime: 0, name: "Helper", app: AppKey(key: "/B.app", name: "Helper"),
                         slices: [Slice(start: 0, end: 10, value: 20, peak: 20)])
    #expect(AppSeries.ranking([a, b], from: 0, to: 10, bucket: 10).count == 2)
    let points = AppSeries.stacked([a, b], from: 0, to: 10, bucket: 10)
    #expect(value(points, 0, "/A.app") == 10)
    #expect(value(points, 0, "/B.app") == 20)
}

@Test func rankingOrdersByAverageWithPeak() {
    let t = [
        track(1, "A", [(0, 10, 10, 15)], name: "a1"),
        track(2, "A", [(0, 5, 40, 90), (5, 10, 0, 0)], name: "a2"),
        track(3, "B", [(0, 10, 50, 55)], name: "b1"),
    ]
    let ranks = AppSeries.ranking(t, from: 0, to: 10, bucket: 10)
    #expect(ranks.map(\.app.key) == ["B", "A"])
    #expect(ranks[0].average == 50)
    #expect(ranks[1].average == 30)  // 10 + 20
    #expect(ranks[1].peak == 30)  // one bucket: the app's average
    #expect(ranks[1].processes.map(\.name) == ["a2", "a1"])
    #expect(ranks[1].processes.map(\.average) == [20, 10])
    #expect(ranks[1].processes.map(\.peak) == [90, 15])
}

@Test func appPeakIsSummedBucketPeak() throws {
    let t = [track(1, "A", [(0, 10, 10, 99)], name: "a1"), track(2, "A", [(5, 15, 20, 99)], name: "a2")]
    let rank = try #require(AppSeries.ranking(t, from: 0, to: 20, bucket: 5).first)
    #expect(rank.peak == 30)  // [5, 10): 10 + 20
    #expect(rank.average == 15)
    #expect(rank.processes.map(\.peak) == [99, 99])

    let ranks = AppSeries.ranking(randomTracks(), from: 0, to: 100, bucket: 7)
    #expect(ranks.allSatisfy { $0.peak >= $0.average })
}

@Test func colorIndexIsStable() {
    let keys = (0..<50).map { AppKey(key: "/Apps/App\($0).app", name: "x") }
    let first = keys.map { AppColor.index(for: $0, paletteSize: 12) }
    #expect(first == keys.map { AppColor.index(for: $0, paletteSize: 12) })
    #expect(first.allSatisfy { (0..<12).contains($0) })
    #expect(Set(first).count > 6)
}

@Test func topAppsGetDistinctSlots() throws {
    let keys = (0..<50).map { AppKey(key: "/Apps/App\($0).app", name: "x") }
    let home = AppColor.index(for: keys[0], paletteSize: 10)
    let rival = try #require(keys.dropFirst().first { AppColor.index(for: $0, paletteSize: 10) == home })
    let slots = AppColor.slots(for: [keys[0], rival], paletteSize: 10)
    #expect(slots == [keys[0]: home, rival: (home + 1) % 10])
    #expect(AppColor.slots(for: [keys[0], rival], paletteSize: 10) == slots)
    // Rank order decides who keeps the shared slot.
    #expect(AppColor.slots(for: [rival, keys[0]], paletteSize: 10) == [rival: home, keys[0]: (home + 1) % 10])
}

@Test func spanRankingIgnoresSlicesOutsideSpan() {
    let t = [
        track(1, "A", [(0, 10, 100, 100), (10, 20, 10, 12)], name: "a1"),
        track(2, "B", [(0, 10, 50, 50)], name: "b1"),
    ]
    let ranks = AppSeries.ranking(t, from: 10, to: 20, bucket: 10)
    #expect(ranks.map(\.app.key) == ["A"])
    #expect(ranks[0].average == 10)
    #expect(ranks[0].peak == 10)
    #expect(ranks[0].processes.map(\.name) == ["a1"])
    #expect(ranks[0].processes[0].peak == 12)
}

@Test func tiesBreakByKeyAndPid() {
    let t = [
        track(3, "b", [(0, 10, 10, 10)]), track(1, "c", [(0, 10, 10, 10)]),
        track(2, "a", [(0, 10, 10, 10)]), track(4, "a", [(0, 10, 10, 10)]),
    ]
    let ranks = AppSeries.ranking(t, from: 0, to: 10, bucket: 10)
    #expect(ranks.map(\.app.key) == ["a", "b", "c"])
    #expect(ranks[0].processes.map(\.pid) == [2, 4])

    let seven = (0..<7).map { track(Int64($0), "k\(6 - $0)", [(0, 10, 10, 10)]) }
    let points = AppSeries.stacked(seven, from: 0, to: 10, bucket: 10)
    #expect(points.compactMap(\.app?.key) == ["k0", "k1", "k2", "k3", "k4"])
}

private func exited(lastSeen: Double, before: Double) -> Bool {
    let t = ProcessTrack(processID: 1, pid: 1, startTime: 0, name: "p", app: AppKey(key: "A", name: "A"), lastSeen: lastSeen,
                         slices: [Slice(start: 0, end: 10, value: 1, peak: 1)])
    return AppSeries.ranking([t], from: 0, to: 10, bucket: 10, exitedBefore: before)[0].processes[0].exited
}

@Test func exitedIsLastSeenBeforeThreshold() {
    // History: now - 70 is still alive, one second older is exited.
    #expect(!exited(lastSeen: 930, before: 1000 - 70))
    #expect(exited(lastSeen: 929, before: 1000 - 70))
}

@Test func liveProcessMissingFromLatestSnapshotIsExited() {
    func proc(_ pid: Int32) -> LiveProcess {
        LiveProcess(pid: pid, startTime: 1, name: "p\(pid)", appKey: "/A.app", appName: "A", path: nil, cpu: 1,
                    mem: 0, diskR: 0, diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: 0)
    }
    func snap(_ ts: Double, _ pids: [Int32]) -> LiveSnapshot {
        LiveSnapshot(ts: ts, system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 0, thermalState: 0), processes: pids.map(proc))
    }
    let tracks = LiveTracks.build([snap(0, [1, 2]), snap(1, [1])], metric: .cpu)
    let procs = AppSeries.ranking(tracks, from: 0, to: 2, bucket: 1, exitedBefore: 1)[0].processes
    #expect(procs.first { $0.pid == 1 }?.exited == false)
    #expect(procs.first { $0.pid == 2 }?.exited == true)
}

@Test func recordedStartIsTheEarliestSliceWithinTheRange() {
    let t = [track(1, "A", [(40, 50, 1, 1)]), track(2, "B", [(30, 35, 1, 1), (60, 70, 1, 1)])]
    #expect(AppSeries.recordedStart(t, from: 0) == 30)
    // Recording older than the range: the range start holds.
    #expect(AppSeries.recordedStart(t, from: 45) == 45)
    #expect(AppSeries.recordedStart([], from: 10) == 10)
}

@Test func backfillJoinsOneProcessAndKeepsExitedOnes() {
    func t(_ id: Int64, pid: Int32, _ slices: [(Double, Double)]) -> ProcessTrack {
        ProcessTrack(processID: id, pid: pid, startTime: 7, name: "p", app: AppKey(key: "A", name: "A"),
                     slices: slices.map { Slice(start: $0.0, end: $0.1, value: 1, peak: 1) })
    }
    let raw = [t(5, pid: 1, [(0, 50), (50, 100)]), t(6, pid: 2, [(60, 80)]), t(7, pid: 3, [(0, 40)])]
    let live = [t(0, pid: 1, [(100, 101)]), t(0, pid: 4, [(100, 101)])]
    let merged = LiveTracks.backfilled(live, raw: raw, from: 50)
    // pid 3 ended before `from`; pid 1 keeps one track with its raw slice first.
    #expect(merged.map(\.pid).sorted() == [1, 2, 4])
    #expect(merged.first { $0.pid == 1 }!.slices.map(\.start) == [50, 100])
    #expect(merged.first { $0.pid == 1 }!.processID == 0)
}

@Test func searchMatchesNamesPathAndExactPID() {
    func rank(_ key: String, _ name: String, _ procs: [(Int32, String)]) -> AppRank {
        AppRank(app: AppKey(key: key, name: name), average: 1, peak: 1, processes: procs.map {
            ProcessRank(processID: Int64($0.0), pid: $0.0, startTime: 0, name: $0.1, average: 1, peak: 1, lastSeen: 0, exited: false)
        })
    }
    let apps = [rank("/Applications/Café.app", "Café", [(12, "Café"), (13, "Café Helper")]),
                rank("node", "node", [(123, "node")])]
    #expect(AppSearch.filter(apps, query: "").count == 2)
    #expect(AppSearch.filter(apps, query: "cafe").map(\.app.name) == ["Café"])
    #expect(AppSearch.filter(apps, query: "cafe")[0].processes.count == 2)
    #expect(AppSearch.filter(apps, query: "/applications").map(\.app.name) == ["Café"])
    // Only a process matches: the app stays with just that process.
    #expect(AppSearch.filter(apps, query: "helper")[0].processes.map(\.pid) == [13])
    // A PID matches exactly, never as a prefix.
    #expect(AppSearch.filter(apps, query: "12").flatMap { $0.processes.map(\.pid) } == [12])
    #expect(AppSearch.filter(apps, query: "123").map(\.app.name) == ["node"])
}
