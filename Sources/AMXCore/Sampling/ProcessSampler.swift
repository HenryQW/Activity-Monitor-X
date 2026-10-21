import Foundation

/// Turns cumulative per-process counters into per-second rates between ticks.
public final class ProcessSampler {
    public init() {}

    private var previous: [ProcessIdentity: RawProcess] = [:]
    private var previousGPU: [ProcessIdentity: UInt64] = [:]
    private var previousNow: Double?

    public func sample(now: Double, gpuNanos: [Int32: UInt64] = [:]) -> (samples: [ProcessSample], new: [RawProcess]) {
        sample(now: now, raw: ProcessReader.listPIDs().compactMap(ProcessReader.read(pid:)), gpuNanos: gpuNanos)
    }

    func sample(now: Double, raw: [RawProcess], gpuNanos: [Int32: UInt64])
        -> (samples: [ProcessSample], new: [RawProcess]) {
        let wall = previousNow.map { now - $0 } ?? 0
        let valid = wall > 0 && wall <= 60
        var samples: [ProcessSample] = []
        var new: [RawProcess] = []
        var nextGPU: [ProcessIdentity: UInt64] = [:]

        for cur in raw {
            let id = cur.identity
            let gpuNow = gpuNanos[id.pid]
            if let gpuNow { nextGPU[id] = gpuNow }
            var cpu = 0.0, diskR = 0.0, diskW = 0.0, energy = 0.0, gpu = 0.0
            if let prev = previous[id] {
                if valid {
                    cpu = CPUMath.percent(cpuDelta: CPUMath.delta(cur.cpuNanos, prev.cpuNanos), wallDelta: wall)
                    diskR = Double(CPUMath.delta(cur.diskRead, prev.diskRead)) / wall
                    diskW = Double(CPUMath.delta(cur.diskWritten, prev.diskWritten)) / wall
                    let wakeups = Double(CPUMath.delta(cur.wakeups, prev.wakeups)) / wall
                    energy = CPUMath.energy(cpu: cpu, wakeupsPerSec: wakeups, translated: cur.translated)
                    if let gpuNow, let gpuPrev = previousGPU[id] {
                        gpu = min(100, Double(CPUMath.delta(gpuNow, gpuPrev)) / (wall * 1e9) * 100)
                    }
                }
            } else {
                new.append(cur)
            }
            samples.append(ProcessSample(identity: id, cpu: cpu, mem: cur.footprint, diskR: diskR, diskW: diskW,
                                         energy: energy, gpu: gpu, netIn: 0, netOut: 0))
        }

        previous = Dictionary(raw.map { ($0.identity, $0) }, uniquingKeysWith: { $1 })
        previousGPU = nextGPU
        previousNow = now
        return (samples, new)
    }
}
