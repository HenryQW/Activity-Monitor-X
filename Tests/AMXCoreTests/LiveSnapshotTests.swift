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

    @Test func liveSnapshotWithoutNewFieldsDecodes() throws {
        let json = """
            {"pid":1,"startTime":2,"name":"p","appKey":"p","appName":"p","cpu":0,"mem":0,"diskR":0,"diskW":0,
             "netIn":0,"netOut":0,"gpu":0,"energy":0}
            """
        let p = try JSONDecoder().decode(LiveProcess.self, from: Data(json.utf8))
        #expect(p.bundleID == nil && p.teamID == nil)
    }

    @Test func liveScore() {
        let p = LiveProcess(pid: 7, startTime: 1, name: "p", appKey: "p", appName: "p", path: nil, cpu: 100, mem: 0,
                            diskR: 0, diskW: 0, netIn: 0, netOut: 0, gpu: 0, energy: 0)
        let snap = LiveSnapshot(ts: 0, system: LiveSystem(cpu: 0, memUsed: 0, pressureLevel: 0, thermalState: 0), processes: [p])
        let device = Device(cores: 10, memory: 17_179_869_184)
        #expect(LiveTracks.build([snap], metric: .score, device: device)[0].slices[0].value == 5)
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
    let track = LiveTracks.build(snapshots, metric: .cpu)[0]
    // The snapshot before the 9 s gap holds 2 s, not until the next one.
    #expect(track.slices.map { [$0.start, $0.end, $0.value] } == [[0, 1, 10], [1, 3, 20], [10, 11, 30]])
    #expect(track.app == AppKey(key: "/A.app", name: "A"))
    #expect(LiveTracks.build(snapshots, metric: .disk)[0].slices[0].value == 5)
}
