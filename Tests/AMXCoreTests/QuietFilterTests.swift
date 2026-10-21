import Testing
@testable import AMXCore

private func track(_ id: Int64, _ app: String, path: String?, _ value: Double) -> ProcessTrack {
    ProcessTrack(processID: id, pid: Int32(id), startTime: 0, name: app, app: AppKey(key: app, name: app), path: path,
                 slices: [Slice(start: 0, end: 10, value: value, peak: value)])
}

@Test func systemPaths() {
    #expect(QuietFilter.isSystem(path: "/System/Library/x"))
    #expect(QuietFilter.isSystem(path: "/usr/libexec/x"))
    #expect(!QuietFilter.isSystem(path: "/usr/local/bin/x"))
    #expect(QuietFilter.isSystem(path: "/sbin/launchd"))
    #expect(QuietFilter.isSystem(path: "/bin/sh"))
    #expect(!QuietFilter.isSystem(path: "/Applications/X.app/Contents/MacOS/X"))
    #expect(!QuietFilter.isSystem(path: nil))
    #expect(QuietFilter.isSystem(path: "/System/Applications/Mail.app/Contents/MacOS/Mail"))
}

@Test func quietAtThresholdBoundary() {
    let t = [track(0, "a", path: "/usr/bin/a", 0.99), track(1, "b", path: "/usr/bin/b", 1.0)]
    #expect(QuietFilter.hidden(t, metric: .cpu, from: 0, to: 10) == [0])
}

@Test func busySystemProcessShows() {
    let t = [track(0, "a", path: "/System/a", 50)]
    #expect(QuietFilter.hidden(t, metric: .cpu, from: 0, to: 10).isEmpty)
}

@Test func nonSystemQuietProcessShows() {
    let t = [track(0, "a", path: "/Applications/A.app/a", 0), track(1, "b", path: nil, 0)]
    #expect(QuietFilter.hidden(t, metric: .cpu, from: 0, to: 10).isEmpty)
}

@Test func averageIsOverTheWholeWindow() {
    // 10 for 1 s of a 10 s window averages 1: shown.
    let t = [ProcessTrack(processID: 0, pid: 0, startTime: 0, name: "a", app: AppKey(key: "a", name: "a"), path: "/bin/a",
                          slices: [Slice(start: 0, end: 1, value: 10, peak: 10)])]
    #expect(QuietFilter.hidden(t, metric: .cpu, from: 0, to: 10).isEmpty)
    #expect(QuietFilter.hidden(t, metric: .cpu, from: 0, to: 100) == [0])
}

@Test func hiddenValuesGoToOther() {
    let t = [track(0, "big", path: "/Applications/B", 50), track(1, "quiet", path: "/usr/bin/q", 0.5),
             track(2, "mid", path: "/Applications/M", 5)]
    let hidden = QuietFilter.hidden(t, metric: .cpu, from: 0, to: 10)
    #expect(hidden == [1])
    let all = AppSeries.stacked(t, from: 0, to: 10, bucket: 10)
    let filtered = AppSeries.stacked(t, from: 0, to: 10, bucket: 10, otherOnly: hidden)
    #expect(filtered.reduce(0) { $0 + $1.value } == all.reduce(0) { $0 + $1.value })
    #expect(!filtered.contains { $0.app?.key == "quiet" })
    #expect(filtered.first { $0.app == nil }?.value == 0.5)
    #expect(AppSeries.ranking(t, from: 0, to: 10, bucket: 10, excluding: hidden).map(\.app.key) == ["big", "mid"])
    #expect(AppSeries.sparklines(t, from: 0, to: 10, count: 2, excluding: hidden).keys.map(\.key).sorted() == ["big", "mid"])
}
