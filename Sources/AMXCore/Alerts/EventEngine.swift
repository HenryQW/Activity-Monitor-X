import Foundation

public enum EventKind {
    public static let pressure = "pressure", thermal = "thermal", alert = "alert"
}

/// The `rule` of an alert row; the keys of `AlertRules`.
public enum RuleName {
    public static let sustainedCPU = "sustained_cpu", memoryGrowth = "memory_growth", memoryJump = "memory_jump"
    public static let pressure = "pressure", thermal = "thermal"
    public static let all = [sustainedCPU, memoryGrowth, memoryJump, pressure, thermal]
}

/// An `events` row before it has a `process_id`; the writer maps `identity` to it.
public struct EventDraft: Sendable, Equatable {
    public let ts: Double
    public let kind: String
    public let severity: Int
    public let identity: ProcessIdentity?
    public let rule: String?
    public let message: String
    public let value: Double?
}

/// Alert limits that are not user settings.
enum AlertLimits {
    /// A longer gap since the previous tick (sleep) restarts every ring and spell.
    static let maxGap = 30.0
    static let pressureCooldown = 600.0
    /// A new sustained CPU spell of an app alerts only this long after its last alert.
    static let cpuRearm = 3600.0
    static let growthRSquared = 0.9
    /// Memory growth needs the last point above the point this many minutes earlier.
    static let stillGrowingMinutes = 5
    static let jumpTicks = 10
    static let jumpQuiet = 1800.0
    /// The pressure cause looks back this many minutes. Needs `memoryGrowth.minutes >= causeMinutes`
    /// (validation keeps it), as the cause reads the growth ring.
    static let causeMinutes = 10
}

/// Owns every event rule. Pure: it sees only the tick's samples and keeps its state in memory.
/// Steps fire on change from the last tick; the first tick only sets the baseline. Re-arm state (CPU, growth,
/// pressure) is in memory only, so after a daemon restart one repeat alert per busy app is possible.
public struct EventEngine: Sendable {
    private var known: [ProcessIdentity: (name: String, app: AppInfo)] = [:]
    private var pressure: Int?
    private var thermal: Int?
    private var lastPressureAlert: Double?
    private var lastTick: Double?
    private(set) var processRules = ProcessRules()
    /// The first tick of the current spell at or above the thermal rule's state, and whether it alerted.
    private var hot: (since: Double, alerted: Bool)?

    public init() {}

    public mutating func evaluate(now: Double, processes: [ProcessSample], new: [(RawProcess, AppInfo)],
                                  system: SystemSample, rules: AlertRules) -> [EventDraft] {
        for (raw, app) in new { known[raw.identity] = (raw.name, app) }
        let live = Set(processes.map(\.identity))
        known = known.filter { live.contains($0.key) }
        if let lastTick, now - lastTick > AlertLimits.maxGap {
            processRules.restartSpells()
            hot = nil
        }
        lastTick = now

        let alerts = processRules.evaluate(now: now, samples: processes, known: known, rules: rules)
        var out: [EventDraft] = []
        if let pressure, pressure != system.pressureLevel {
            out.append(pressureStep(now: now, from: pressure, processes: processes, system: system,
                                    rules: rules.pressure))
        }
        if let thermal, thermal != system.thermalState {
            out.append(EventDraft(ts: now, kind: EventKind.thermal, severity: system.thermalState, identity: nil,
                                  rule: nil, message: "Thermal state \(SystemState.thermal(system.thermalState))",
                                  value: Double(system.thermalState)))
        }
        if let alert = thermalAlert(now: now, state: system.thermalState, rule: rules.thermal) { out.append(alert) }
        pressure = system.pressureLevel
        thermal = system.thermalState
        return out + alerts
    }

    private static func severity(pressure level: Int) -> Int { [1: 0, 2: 1, 4: 2][level] ?? 0 }

    /// Only a rising step can alert, so warning after critical does not.
    private mutating func pressureStep(now: Double, from old: Int, processes: [ProcessSample], system: SystemSample,
                                       rules: AlertRules.Pressure) -> EventDraft {
        let severity = Self.severity(pressure: system.pressureLevel)
        let rising = severity > Self.severity(pressure: old)
        let grower = processRules.topGrower(processes, now: now)
        let top = processes.max { $0.mem < $1.mem }
        var message = "Memory pressure \(SystemState.pressure(system.pressureLevel))"
        if rising, let grower, let who = who(grower.identity) {
            message += ": \(who) grew \(Self.bytes(grower.growth)) in \(grower.minutes) min"
        } else if rising, let top, let who = who(top.identity) {
            message += ": \(who) uses the most memory (\(Self.bytes(top.mem)))"
        }
        var rule: String?
        if rules.enabled, severity >= rules.level.severity, rising,
           lastPressureAlert.map({ now - $0 >= AlertLimits.pressureCooldown }) ?? true {
            rule = RuleName.pressure
            lastPressureAlert = now
        }
        return EventDraft(ts: now, kind: EventKind.pressure, severity: severity,
                          identity: grower?.identity ?? top?.identity, rule: rule, message: message,
                          value: system.pressurePct)
    }

    /// One alert per spell at or above the rule's state; a drop below it re-arms the rule.
    private mutating func thermalAlert(now: Double, state: Int, rule: AlertRules.Thermal) -> EventDraft? {
        guard rule.enabled, state >= rule.state.rawState else {
            hot = nil
            return nil
        }
        let spell = hot ?? (now, false)
        hot = spell
        guard !spell.alerted, now - spell.since >= Double(rule.minutes * 60) else { return nil }
        hot?.alerted = true
        return EventDraft(ts: now, kind: EventKind.alert, severity: state == 3 ? 2 : 1, identity: nil, rule: RuleName.thermal,
                          message: "Thermal state \(SystemState.thermal(state)) for \(rule.minutes) min",
                          value: Double(state))
    }

    private func who(_ identity: ProcessIdentity) -> String? { known[identity].map(Self.who) }

    /// The process name, plus its app name when the two differ.
    static func who(_ entry: (name: String, app: AppInfo)) -> String {
        entry.app.appName == entry.name ? entry.name : "\(entry.name) (\(entry.app.appName))"
    }

    /// `x.x GB` from 1 GiB, else `n MB`, in binary units. GB starts where MB would
    /// round to 1024.
    static func bytes(_ count: UInt64) -> String {
        let mib = Double(count) / 1_048_576
        return mib >= 1023.5 ? String(format: "%.1f GB", mib / 1024) : "\(Int(mib.rounded())) MB"
    }
}
