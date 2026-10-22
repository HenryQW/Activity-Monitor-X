import Testing
@testable import AMXCore

private let gib: UInt64 = 1 << 30
private let idA = ProcessIdentity(pid: 10, startTime: 100)
private let idB = ProcessIdentity(pid: 11, startTime: 101)

private func raw(_ id: ProcessIdentity) -> (RawProcess, AppInfo) {
    (RawProcess(identity: id, name: "p\(id.pid)", path: nil, uid: 501, cpuNanos: 0, footprint: 0, diskRead: 0,
                diskWritten: 0, wakeups: 0, translated: false),
     AppInfo(appPath: nil, appName: "p\(id.pid)", bundleID: nil))
}

private func sample(_ id: ProcessIdentity, mem: UInt64) -> ProcessSample {
    ProcessSample(identity: id, cpu: 0, mem: mem, diskR: 0, diskW: 0, energy: 0, gpu: 0, netIn: 0, netOut: 0)
}

private func system(pressure: Int = 1, thermal: Int = 0) -> SystemSample {
    var s = SystemSample()
    s.pressureLevel = pressure
    s.thermalState = thermal
    return s
}

private struct Rig {
    var engine = EventEngine()
    var rules = AlertRules()

    mutating func tick(_ now: Double, pressure: Int = 1, thermal: Int = 0, processes: [ProcessSample] = [],
                       new: [ProcessIdentity] = []) -> [EventDraft] {
        engine.evaluate(now: now, processes: processes, new: new.map(raw),
                        system: system(pressure: pressure, thermal: thermal), rules: rules)
    }
}

@Suite struct EventEngineTests {
    @Test func firstTickIsBaseline() {
        var r = Rig()
        #expect(r.tick(0, pressure: 2, thermal: 2).isEmpty)
    }

    @Test func pressureEventOnlyOnChange() {
        var r = Rig()
        let processes = [sample(idA, mem: gib), sample(idB, mem: 3 * gib)]
        var drafts: [EventDraft] = []
        for (i, level) in [1, 1, 2, 2, 4].enumerated() {
            drafts += r.tick(Double(i) * 5, pressure: level, processes: processes, new: i == 0 ? [idA, idB] : [])
        }
        #expect(drafts.map(\.severity) == [1, 2])
        #expect(drafts.allSatisfy { $0.kind == EventKind.pressure && $0.identity == idB })
        #expect(drafts.last?.message == "Memory pressure critical: p11 uses the most memory (3.0 GB)")
    }

    @Test func pressureAlertAtRuleLevel() {
        var r = Rig()
        _ = r.tick(0)
        #expect(r.tick(5, pressure: 2).map(\.rule) == ["pressure"])
        _ = r.tick(10, pressure: 4)
        // Past the cooldown, but a falling step never alerts.
        #expect(r.tick(700, pressure: 2).map(\.rule) == [nil])
        #expect(r.tick(705, pressure: 4).map(\.rule) == ["pressure"])

        var critical = Rig()
        critical.rules.pressure.level = .critical
        _ = critical.tick(0)
        #expect(critical.tick(5, pressure: 2).map(\.rule) == [nil])
        #expect(critical.tick(10, pressure: 4).map(\.rule) == ["pressure"])
    }

    @Test func pressureAlertCooldown() {
        var r = Rig()
        _ = r.tick(-5)
        #expect(r.tick(0, pressure: 2).map(\.rule) == ["pressure"])
        let down = r.tick(60)
        #expect(down.map(\.severity) == [0] && down.map(\.rule) == [nil])
        #expect(r.tick(120, pressure: 2).map(\.rule) == [nil])
        _ = r.tick(595)
        // Exactly 600 s after the last alert: the cooldown has ended (>=).
        #expect(r.tick(600, pressure: 2).map(\.rule) == ["pressure"])
        _ = r.tick(650)
        #expect(r.tick(700, pressure: 2).map(\.rule) == [nil])
    }

    @Test func thermalEventOnChange() {
        var r = Rig()
        _ = r.tick(0)
        let drafts = r.tick(5, thermal: 2)
        #expect(drafts.count == 1)
        #expect(drafts.first?.kind == EventKind.thermal && drafts.first?.severity == 2)
        #expect(drafts.first?.identity == nil && drafts.first?.rule == nil)
    }

    @Test func thermalAlertAfterHold() {
        var r = Rig()
        var alerts: [EventDraft] = []
        func alertsUntil(_ end: Double, from start: Double, thermal: Int) {
            for t in stride(from: start, through: end, by: 5) {
                alerts += r.tick(t, thermal: thermal).filter { $0.kind == EventKind.alert }
            }
        }
        alertsUntil(295, from: 0, thermal: 2)
        #expect(alerts.isEmpty)
        alertsUntil(600, from: 300, thermal: 2)
        #expect(alerts.map(\.ts) == [300])
        #expect(alerts.first?.rule == "thermal" && alerts.first?.severity == 1)
        #expect(alerts.first?.message == "Thermal state serious for 5 min" && alerts.first?.value == 2)
        alertsUntil(605, from: 605, thermal: 1)
        alertsUntil(910, from: 610, thermal: 2)
        #expect(alerts.map(\.ts) == [300, 910])
    }

    @Test func byteText() {
        #expect([EventEngine.bytes(1_073_217_536), EventEngine.bytes(1_073_217_535)] == ["1.0 GB", "1023 MB"])
    }

    @Test func disabledRulesSetNoRule() {
        var r = Rig()
        r.rules.sustainedCPU.enabled = false
        r.rules.memoryGrowth.enabled = false
        r.rules.memoryJump.enabled = false
        r.rules.pressure.enabled = false
        r.rules.thermal.enabled = false
        var drafts: [EventDraft] = []
        for (i, level) in [1, 2, 4, 1].enumerated() { drafts += r.tick(Double(i) * 5, pressure: level, thermal: 3) }
        for t in stride(from: 20.0, through: 600, by: 5) { drafts += r.tick(t, thermal: t < 300 ? 3 : 2) }
        #expect(drafts.map(\.kind) == [EventKind.pressure, EventKind.pressure, EventKind.pressure, EventKind.thermal])
        #expect(drafts.allSatisfy { $0.rule == nil })
    }
}
