@testable import AMXCore
import Testing

@Suite struct NVMeHealthTests {
    /// A 512-byte log page with little-endian fields at the NVMe offsets.
    private func log(warning: UInt8 = 0, kelvin: UInt16 = 310, spare: UInt8 = 100, threshold: UInt8 = 10,
                     counters: [Int: UInt64] = [:]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 512)
        b[0] = warning
        b[1] = UInt8(kelvin & 0xFF)
        b[2] = UInt8(kelvin >> 8)
        b[3] = spare
        b[4] = threshold
        b[5] = 3
        for (offset, value) in counters {
            for i in 0..<8 { b[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        return b
    }

    @Test func parsesSMARTLog() throws {
        let h = try #require(NVMeHealth.parse(log(counters: [32: 1_000, 48: 2_000, 112: 50, 128: 1_234, 144: 7])))
        #expect(abs(try #require(h.temperatureCelsius) - 36.85) < 1e-9)
        #expect(h.availableSpare == 100 && h.spareThreshold == 10 && h.percentageUsed == 3)
        #expect(h.dataReadBytes == 512_000_000)
        #expect(h.dataWrittenBytes == 1_024_000_000)
        #expect(h.powerCycles == 50 && h.powerOnHours == 1_234 && h.unsafeShutdowns == 7 && h.mediaErrors == 0)
        #expect(h.isHealthy)
    }

    @Test func zeroKelvinIsNil() {
        #expect(NVMeHealth.parse(log(kelvin: 0))?.temperatureCelsius == nil)
    }

    @Test func shortLogIsNil() {
        #expect(NVMeHealth.parse([UInt8](repeating: 0, count: 511)) == nil)
    }

    @Test func unhealthyWhenWarnedOrSpareLow() {
        #expect(NVMeHealth.parse(log(warning: 0x04))?.isHealthy == false)
        #expect(NVMeHealth.parse(log(spare: 5, threshold: 10))?.isHealthy == false)
    }
}
