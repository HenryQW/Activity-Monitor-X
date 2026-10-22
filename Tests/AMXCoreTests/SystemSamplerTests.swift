@testable import AMXCore
import Foundation
import Testing

@Suite struct SystemSamplerTests {
    @Test func pressureIndexFloors() {
        #expect(PressureIndex.percent(level: 1, compressed: 0, swap: 0, ram: 1 << 34, growthBytesPerSec: 0) == 0)
        #expect(PressureIndex.percent(level: 2, compressed: 0, swap: 0, ram: 1 << 34, growthBytesPerSec: 0) == 34)
        #expect(PressureIndex.percent(level: 4, compressed: 0, swap: 0, ram: 1 << 34, growthBytesPerSec: 0) == 67)
    }

    @Test func pressureIndexSaturates() {
        let ram: UInt64 = 1 << 34
        #expect(PressureIndex.percent(level: 4, compressed: ram, swap: ram, ram: ram,
                                      growthBytesPerSec: 100_000_000) == 100)
    }

    @Test func diskLatencyZeroOps() {
        #expect(DiskMath.latencyMs(timeDeltaNanos: 2_000_000, opsDelta: 0) == 0)
    }

    @Test func diskLatencyMs() {
        #expect(DiskMath.latencyMs(timeDeltaNanos: 2_000_000, opsDelta: 4) == 0.5)
    }

    @Test func perDiskRates() {
        let zero = DiskCounters(bsdName: "disk0", readBytes: 0, writeBytes: 0, reads: 0, writes: 0, readNanos: 0, writeNanos: 0)
        let a = DiskCounters(bsdName: "disk0", readBytes: 10_000_000, writeBytes: 5_000_000, reads: 100, writes: 100,
                             readNanos: 100_000_000, writeNanos: 100_000_000)
        var b = zero
        b.bsdName = "disk1"
        let rates = DiskMath.rates(current: [1: a, 2: b], previous: [1: zero], wall: 2)
        #expect(rates == ["disk0": DiskRate(readBps: 5e6, writeBps: 2.5e6, iops: 100, latencyMs: 1, utilPct: 10)])
    }

    @Test func totalWeightsLatency() {
        let t = DiskMath.total([DiskRate(readBps: 1, writeBps: 2, iops: 100, latencyMs: 1, utilPct: 10),
                                DiskRate(readBps: 3, writeBps: 4, iops: 300, latencyMs: 3, utilPct: 60)])
        #expect(t == DiskRate(readBps: 4, writeBps: 6, iops: 400, latencyMs: 2.5, utilPct: 60))
    }

    @Test func systemSampleSmoke() async throws {
        let sampler = SystemSampler()
        _ = sampler.sample(now: Date().timeIntervalSince1970)
        try await Task.sleep(for: .milliseconds(200))
        let s = sampler.sample(now: Date().timeIntervalSince1970)
        #expect([1, 2, 4].contains(s.pressureLevel))
        #expect((0...100).contains(s.cpu))
        #expect(s.memUsed > 0)
        #expect((s.diskFree ?? 0) > 0)
        #expect((0...3).contains(s.thermalState))
    }

    @Test func readoutSmoke() async throws {
        let sampler = SystemSampler()
        _ = sampler.readout(now: Date().timeIntervalSince1970)
        try await Task.sleep(for: .seconds(1))
        let r = sampler.readout(now: Date().timeIntervalSince1970)
        #expect((0...100).contains(r.cpu))
        #expect([1, 2, 4].contains(r.pressureLevel))
        #expect((0...100).contains(r.pressurePct))
    }

    /// Reads the real SMC. 5 s ticks arrive with jitter, so a read 4 s after the last one is not skipped.
    @Test func smcThrottleUnderFourSeconds() throws {
        let smc = SMCReader()
        _ = smc.read(now: 1000)
        try #require(smc.lastRead == 1000)
        _ = smc.read(now: 1004)
        #expect(smc.lastRead == 1004)
        _ = smc.read(now: 1007.9)
        #expect(smc.lastRead == 1004)
    }

    @Test func perCoreDeltas() {
        typealias T = SystemSampler.CoreTicks
        let prev = [T(busy: 10, idle: 90), T(busy: UInt32.max, idle: 0)]
        let now = [T(busy: 60, idle: 140), T(busy: 4, idle: 0)]
        #expect(SystemSampler.corePercents(now, prev) == [50, 100])
        #expect(SystemSampler.corePercents(now, [prev[0]]).isEmpty)
    }

    @Test func clusterIndexesStartWithSlowestLevel() {
        let chip = ChipInfo(name: "", model: "", clusters: [.init(name: "Super", cores: 5), .init(name: "Performance", cores: 10)], memory: 0)
        #expect(chip.cpuIndexes(cluster: 0) == 10..<15)
        #expect(chip.cpuIndexes(cluster: 1) == 0..<10)
    }
}
