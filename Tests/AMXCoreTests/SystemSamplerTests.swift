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

    @Test func systemSampleSmoke() async throws {
        let sampler = SystemSampler()
        _ = sampler.sample(now: Date().timeIntervalSince1970)
        try await Task.sleep(for: .milliseconds(200))
        let s = sampler.sample(now: Date().timeIntervalSince1970)
        #expect([1, 2, 4].contains(s.pressureLevel))
        #expect((0...100).contains(s.cpu))
        #expect(s.memUsed > 0)
        #expect((0...3).contains(s.thermalState))
    }
}
