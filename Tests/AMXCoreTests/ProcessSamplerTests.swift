@testable import AMXCore
import Foundation
import Testing

@Suite struct ProcessSamplerTests {
    private func raw(pid: Int32 = 100, cpu: UInt64 = 0, disk: UInt64 = 0, wakeups: UInt64 = 0,
                     translated: Bool = false) -> RawProcess {
        RawProcess(identity: ProcessIdentity(pid: pid, startTime: 1), name: "p", path: nil, uid: 0,
                   cpuNanos: cpu, footprint: 10, diskRead: disk, diskWritten: disk, wakeups: wakeups,
                   translated: translated)
    }

    @Test func machToNanosAppleSilicon() {
        #expect(CPUMath.machToNanos(3, numer: 125, denom: 3) == 125)
        _ = CPUMath.machToNanos(UInt64.max / 2, numer: 125, denom: 3)
    }

    @Test func cpuPercentOneCore() {
        #expect(CPUMath.percent(cpuDelta: 500_000_000, wallDelta: 1.0) == 50)
        #expect(CPUMath.delta(5, 10) == 0)
    }

    @Test func firstSightingHasZeroRates() {
        let r = ProcessSampler().sample(now: 100, raw: [raw(cpu: 9_000_000_000, disk: 5, wakeups: 5)], gpuNanos: [:])
        #expect(r.new.count == 1)
        let s = r.samples[0]
        #expect(s.cpu == 0 && s.diskR == 0 && s.diskW == 0 && s.energy == 0)
    }

    @Test(arguments: [97.0, 161.0])
    func wallClockJumpGivesZeroRates(second: Double) {
        let sampler = ProcessSampler()
        _ = sampler.sample(now: 100, raw: [raw()], gpuNanos: [:])
        let s = sampler.sample(now: second, raw: [raw(cpu: 1_000_000_000, disk: 100, wakeups: 10)], gpuNanos: [:]).samples[0]
        #expect(s.cpu == 0 && s.diskR == 0 && s.diskW == 0 && s.energy == 0 && s.gpu == 0)
    }

    @Test func steadyTickGivesRates() {
        let sampler = ProcessSampler()
        _ = sampler.sample(now: 100, raw: [raw()], gpuNanos: [:])
        let s = sampler.sample(now: 105, raw: [raw(cpu: 2_500_000_000, disk: 500)], gpuNanos: [:]).samples[0]
        #expect(s.cpu == 50 && s.diskR == 100 && s.diskW == 100)
    }

    @Test func ownProcessIdentityIsStable() throws {
        let a = try #require(ProcessReader.read(pid: getpid()))
        let b = try #require(ProcessReader.read(pid: getpid()))
        #expect(a.identity == b.identity)
        #expect(a.identity.startTime > 0)
    }

    @Test func staticFactsReadOnlyForNewOrExecdProcess() {
        let known = [ProcessIdentity(pid: 100, startTime: 1): raw(translated: true)]
        var reads = 0
        func facts(pid: Int32, start: Double, name: String) -> (path: String?, translated: Bool) {
            ProcessReader.facts(of: ProcessIdentity(pid: pid, startTime: start), name: name, known: known) {
                reads += 1
                return ("/new", false)
            }
        }
        #expect(facts(pid: 100, start: 1, name: "p") == (nil, true))
        #expect(reads == 0)
        #expect(facts(pid: 101, start: 1, name: "p") == ("/new", false))  // new pid, same name
        #expect(facts(pid: 100, start: 2, name: "p") == ("/new", false))  // reused pid
        #expect(facts(pid: 100, start: 1, name: "q") == ("/new", false))  // exec
        #expect(reads == 3)
    }

    @Test func energyFormula() {
        #expect(CPUMath.energy(cpu: 50, wakeupsPerSec: 20, translated: true) == 62)
    }

    @Test func gpuPercentFromNanos() {
        let id = Int32(100)
        let sampler = ProcessSampler()
        _ = sampler.sample(now: 100, raw: [raw()], gpuNanos: [id: 0])
        #expect(sampler.sample(now: 105, raw: [raw()], gpuNanos: [id: 2_500_000_000]).samples[0].gpu == 50)
        let capped = ProcessSampler()
        _ = capped.sample(now: 100, raw: [raw()], gpuNanos: [id: 0])
        #expect(capped.sample(now: 105, raw: [raw()], gpuNanos: [id: 10_000_000_000]).samples[0].gpu == 100)
    }
}
