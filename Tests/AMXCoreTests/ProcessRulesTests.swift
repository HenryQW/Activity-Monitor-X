import Testing
@testable import AMXCore

private let mib: UInt64 = 1 << 20
private let gib: UInt64 = 1 << 30

private struct Proc {
    let id: ProcessIdentity
    let name: String
    let app: AppInfo

    init(_ pid: Int32, _ name: String, appPath: String? = "/A.app", appName: String = "A") {
        id = ProcessIdentity(pid: pid, startTime: Double(pid))
        self.name = name
        app = AppInfo(appPath: appPath, appName: appName, bundleID: nil)
    }

    /// A process that is its own app, so messages name it alone.
    static func solo(_ pid: Int32, _ name: String) -> Proc { Proc(pid, name, appPath: nil, appName: name) }
}

private struct Rig {
    var engine = EventEngine()
    var seen: Set<ProcessIdentity> = []

    mutating func tick(_ now: Double, _ procs: [(Proc, cpu: Double, mem: UInt64)], pressure: Int = 1) -> [EventDraft] {
        let new = procs.filter { seen.insert($0.0.id).inserted }.map { p, _, _ in
            (RawProcess(identity: p.id, name: p.name, path: nil, uid: 501, cpuNanos: 0, footprint: 0, diskRead: 0,
                        diskWritten: 0, wakeups: 0, translated: false), p.app)
        }
        let samples = procs.map { p, cpu, mem in
            ProcessSample(identity: p.id, cpu: cpu, mem: mem, diskR: 0, diskW: 0, energy: 0, gpu: 0, netIn: 0, netOut: 0)
        }
        var system = SystemSample()
        system.pressureLevel = pressure
        return engine.evaluate(now: now, processes: samples, new: new, system: system, rules: AlertRules())
    }

    /// Alerts of one rule over 5 s ticks from `start` up to, not including, `end`.
    mutating func alerts(_ rule: String, from start: Double, to end: Double,
                         _ procs: (Double) -> [(Proc, cpu: Double, mem: UInt64)]) -> [EventDraft] {
        stride(from: start, to: end, by: 5).flatMap { t in tick(t, procs(t)).filter { $0.rule == rule } }
    }
}

@Suite struct ProcessRulesTests {
    @Test func sustainedCPUFiresOncePerSpell() {
        var r = Rig()
        let a1 = Proc(1, "a1"), a2 = Proc(2, "a2")
        func both(_ cpu: Double) -> (Double) -> [(Proc, cpu: Double, mem: UInt64)] {
            { _ in [(a1, cpu / 2, gib), (a2, cpu / 2, gib)] }
        }
        var alerts = r.alerts("sustained_cpu", from: 0, to: 300, both(100))
        #expect(alerts.map(\.ts) == [295])
        #expect(alerts.first?.message == "A used 100 % CPU for 5 min" && alerts.first?.value == 100)
        #expect(alerts.first?.kind == EventKind.alert && alerts.first?.severity == 1)
        #expect([a1.id, a2.id].contains(alerts.first?.identity))
        alerts += r.alerts("sustained_cpu", from: 300, to: 600, both(100))
        alerts += r.alerts("sustained_cpu", from: 600, to: 900, both(10))
        alerts += r.alerts("sustained_cpu", from: 900, to: 1200, both(100))
        #expect(alerts.count == 1)
        alerts += r.alerts("sustained_cpu", from: 1200, to: 3600, both(10))
        alerts += r.alerts("sustained_cpu", from: 3600, to: 3900, both(100))
        #expect(alerts.count == 2)
    }

    @Test func sustainedCPUBelowThresholdIsQuiet() {
        var r = Rig()
        #expect(r.alerts("sustained_cpu", from: 0, to: 600) { _ in [(Proc(1, "a"), 79, gib)] }.isEmpty)
    }

    @Test func sustainedCPUBurstIsQuiet() {
        var r = Rig()
        let a = Proc(1, "a")
        let alerts = r.alerts("sustained_cpu", from: 0, to: 900) { t in [(a, (300..<361).contains(t) ? 400 : 0, gib)] }
        #expect(alerts.isEmpty)
    }

    @Test func sustainedCPUJitterFiresOnce() {
        var r = Rig()
        let a = Proc(1, "a")
        let alerts = r.alerts("sustained_cpu", from: 0, to: 600) { t in [(a, [75, 90, 105][Int(t / 5) % 3], gib)] }
        #expect(alerts.map(\.ts) == [295])
    }

    @Test func sustainedCPURearmSurvivesAppRestart() {
        var r = Rig()
        var alerts = r.alerts("sustained_cpu", from: 0, to: 300) { _ in [(Proc(1, "a"), 100, gib)] }
        _ = r.tick(300, [])
        alerts += r.alerts("sustained_cpu", from: 305, to: 2000) { _ in [(Proc(2, "a"), 100, gib)] }
        alerts += r.alerts("sustained_cpu", from: 2100, to: 3895) { _ in [(Proc(2, "a"), 100, gib)] }  // after a sleep
        #expect(alerts.map(\.ts) == [295])
    }

    @Test func kernelTaskIsExempt() {
        var r = Rig()
        #expect(r.alerts("sustained_cpu", from: 0, to: 600) { _ in [(.solo(0, "kernel_task"), 400, gib)] }.isEmpty)
    }

    @Test func memoryGrowthSteady() {
        var r = Rig()
        let p = Proc.solo(1, "p")
        let steady: (Double) -> [(Proc, cpu: Double, mem: UInt64)] = { t in [(p, 0, gib + 10 * mib * UInt64(t / 60))] }
        var alerts = r.alerts("memory_growth", from: 0, to: 1805, steady)
        #expect(alerts.map(\.ts) == [1800])
        #expect(alerts.first?.message == "p grew by 300 MB in 30 min" && alerts.first?.value == 314_572_800)
        #expect(alerts.first?.identity == p.id)
        alerts += r.alerts("memory_growth", from: 1805, to: 3605, steady)
        #expect(alerts.count == 1)
    }

    @Test func memoryGrowthNoisyIsQuiet() {
        var r = Rig()
        let p = Proc.solo(1, "p")
        let alerts = r.alerts("memory_growth", from: 0, to: 3605) { t in
            let minute = UInt64(t / 60)
            return [(p, 0, gib + 10 * mib * minute + (minute % 2 == 1 ? 200 * mib : 0))]
        }
        #expect(alerts.isEmpty)
    }

    @Test func memoryGrowthFlatTailIsQuiet() {
        var r = Rig()
        let p = Proc.solo(1, "p")
        let alerts = r.alerts("memory_growth", from: 0, to: 3605) { t in
            [(p, 0, gib + 12 * mib * min(UInt64(t / 60), 25))]
        }
        #expect(alerts.isEmpty)
    }

    @Test func memoryJumpStep() {
        var r = Rig()
        let p = Proc.solo(1, "p")
        var alerts = r.alerts("memory_jump", from: 0, to: 50) { t in [(p, 0, t < 25 ? 512 * mib : 2 * gib)] }
        #expect(alerts.map(\.ts) == [45])
        #expect(alerts.first?.message == "p jumped by 1.5 GB" && alerts.first?.value == 1_610_612_736)
        alerts += r.alerts("memory_jump", from: 50, to: 1550) { t in
            [(p, 0, Int((t - 50) / 25) % 2 == 0 ? 512 * mib : 2 * gib)]
        }
        #expect(alerts.count == 1)
    }

    @Test func pressureCauseIsTopGrower() {
        var r = Rig()
        let a = Proc.solo(1, "A"), b = Proc.solo(2, "B")
        var drafts: [EventDraft] = []
        for t in stride(from: 0.0, through: 605, by: 5) {
            drafts += r.tick(t, [(a, 0, 4 * gib), (b, 0, t < 60 ? gib : 2 * gib)], pressure: t < 605 ? 1 : 2)
        }
        let pressure = drafts.filter { $0.kind == EventKind.pressure }
        #expect(pressure.count == 1 && pressure.first?.identity == b.id)
        #expect(pressure.first?.message == "Memory pressure warning: B grew 1.0 GB in 10 min")
        #expect(r.tick(610, [(a, 0, 4 * gib), (b, 0, 2 * gib)]).map(\.message) == ["Memory pressure normal"])
    }

    @Test func pressureCauseSpanIsReal() {
        var r = Rig()
        let a = Proc.solo(1, "A"), b = Proc.solo(2, "B")
        var drafts: [EventDraft] = []
        for t in stride(from: 0.0, through: 605, by: 5) {
            let young = t < 300 ? [] : [(b, cpu: 0.0, mem: t < 360 ? gib : 2 * gib)]
            drafts += r.tick(t, [(a, 0, 4 * gib)] + young, pressure: t < 605 ? 1 : 2)
        }
        #expect(drafts.filter { $0.kind == EventKind.pressure }.map(\.message)
            == ["Memory pressure warning: B grew 1.0 GB in 5 min"])
    }

    @Test func endedProcessStateIsDropped() {
        var r = Rig()
        let a = Proc(1, "a"), b = Proc(2, "b", appPath: "/B.app", appName: "B"),
            c = Proc(3, "c", appPath: "/C.app", appName: "C")
        for t in stride(from: 0.0, to: 100, by: 5) { _ = r.tick(t, [(a, 50, gib), (b, 50, gib), (c, 50, gib)]) }
        #expect(r.engine.processRules.watchedProcesses == 3 && r.engine.processRules.watchedApps == 3)
        _ = r.tick(100, [(a, 50, gib)])
        #expect(r.engine.processRules.watchedProcesses == 1 && r.engine.processRules.watchedApps == 1)
    }

    @Test func sleepGapResets() {
        var r = Rig()
        let a = Proc(1, "a")
        var alerts = r.alerts("sustained_cpu", from: 0, to: 295) { _ in [(a, 100, gib)] }
        alerts += r.tick(350, [(a, 100, gib)]).filter { $0.rule == "sustained_cpu" }
        #expect(alerts.isEmpty)

        var g = Rig()
        let p = Proc.solo(2, "p")
        let steady: (Double) -> [(Proc, cpu: Double, mem: UInt64)] = { t in [(p, 0, gib + 10 * mib * UInt64(t / 60))] }
        #expect(g.alerts("memory_growth", from: 0, to: 1805, steady).count == 1)
        #expect(g.alerts("memory_growth", from: 1860, to: 3800, steady).isEmpty)
    }
}
