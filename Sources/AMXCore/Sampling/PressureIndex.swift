// MIT License. See Packaging/Credits.html.
import Foundation

/// Continuous 0–100 memory pressure index. The kernel level picks a 33-wide band;
/// compression, swap and their growth position the index within it.
enum PressureIndex {
    ///     signal = clamp(0.5·compression + 0.3·swap + 0.2·trend, 0, 1)
    ///     index  = floor(level) + 33 · signal
    static func percent(level: Int, compressed: UInt64, swap: UInt64, ram: UInt64,
                        growthBytesPerSec: Double) -> Double {
        let floor: Double = switch level {
        case 4: 67
        case 2: 34
        default: 0
        }
        let r = Double(ram)
        let compression = r > 0 ? min(Double(compressed) / (0.5 * r), 1) : 0
        let swapSignal = r > 0 ? min(Double(swap) / r, 1) : 0
        let trend = min(max(growthBytesPerSec / 50_000_000, 0), 1)
        let signal = min(max(0.5 * compression + 0.3 * swapSignal + 0.2 * trend, 0), 1)
        return min(floor + 33 * signal, 100)
    }
}
