// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import Foundation

enum CPUMath {
    /// Mach absolute time to nanoseconds. Split form so the multiply cannot overflow.
    static func machToNanos(_ t: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        let n = UInt64(numer), d = UInt64(denom)
        guard n != d else { return t }
        return (t / d) &* n &+ (t % d) &* n / d
    }

    /// Counter delta; 0 when the counter went backwards.
    static func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    /// Percent of one core, uncapped.
    static func percent(cpuDelta: UInt64, wallDelta: Double) -> Double {
        guard wallDelta > 0 else { return 0 }
        return Double(cpuDelta) / (wallDelta * 1e9) * 100
    }

    static func energy(cpu: Double, wakeupsPerSec: Double, translated: Bool) -> Double {
        cpu * (translated ? 1.2 : 1) + wakeupsPerSec * 0.1
    }
}
