// Derived from mac-performance-monitor (Zesty0wl), MIT License. See Packaging/Credits.html.
import Foundation

/// Per-app sustained CPU and per-process memory growth and jump. Pure; rings and spells live only for the
/// processes and apps of the current tick, and an app's last CPU alert time lives for `AlertLimits.cpuRearm`.
struct ProcessRules: Sendable {
    private typealias L = AlertLimits

    private struct App {
        /// The app's CPU sum per tick.
        var sums: [Double] = []
        /// The current spell over the threshold has alerted.
        var alerted = false
    }

    private struct Process {
        /// The footprint at the first tick of each minute.
        var minutes: [(ts: Double, mem: UInt64)] = []
        var minute: Int?
        var grew = false
        /// The footprint per tick.
        var ticks: [UInt64] = []
        var quietUntil = -Double.infinity
    }

    private var apps: [String: App] = [:]
    private var processes: [ProcessIdentity: Process] = [:]
    /// By app key; kept when the app's processes end, so a restarted app does not alert again at once.
    private var lastCPUAlert: [String: Double] = [:]

    /// After a sleep every spell starts again, but the per-app re-arm and the grown processes keep counting (M4-D5).
    mutating func restartSpells() {
        let kept = lastCPUAlert, grown = processes.filter(\.value.grew)
        self = ProcessRules()
        lastCPUAlert = kept
        processes = grown.mapValues { _ in
            var p = Process()
            p.grew = true
            return p
        }
    }

    var watchedProcesses: Int { processes.count }
    var watchedApps: Int { apps.count }

    /// `kernel_task` is skipped: its CPU is thermal management.
    mutating func evaluate(now: Double, samples: [ProcessSample], known: [ProcessIdentity: (name: String, app: AppInfo)],
                           rules: AlertRules) -> [EventDraft] {
        var out: [EventDraft] = []
        var liveProcesses: [ProcessIdentity: Process] = [:]
        var tick: [String: (name: String, cpu: Double, busiest: ProcessSample)] = [:]
        for s in samples {
            guard let entry = known[s.identity], entry.name != "kernel_task" else { continue }
            let (name, app) = entry
            var state = processes.removeValue(forKey: s.identity) ?? Process()
            out += Self.memory(s, entry, &state, now: now, rules: rules)
            liveProcesses[s.identity] = state
            let key = app.appPath ?? name
            let prior = tick[key]
            tick[key] = (app.appName, (prior?.cpu ?? 0) + s.cpu,
                         prior.map { $0.busiest.cpu >= s.cpu ? $0.busiest : s } ?? s)
        }
        processes = liveProcesses

        lastCPUAlert = lastCPUAlert.filter { now - $0.value < L.cpuRearm }
        var liveApps: [String: App] = [:]
        for (key, t) in tick {
            var state = apps.removeValue(forKey: key) ?? App()
            if let mean = Self.cpuAlert(t.cpu, &state, lastAlert: lastCPUAlert[key], now: now,
                                        rule: rules.sustainedCPU) {
                lastCPUAlert[key] = now
                out.append(EventDraft(ts: now, kind: EventKind.alert, severity: 1, identity: t.busiest.identity,
                                      rule: RuleName.sustainedCPU, message: "\(t.name) used \(Int(mean.rounded())) % CPU for "
                                          + "\(rules.sustainedCPU.minutes) min", value: mean))
            }
            liveApps[key] = state
        }
        apps = liveApps
        return out
    }

    /// The process that grew most since its point `causeMinutes` back (or its oldest point, at least 1 min
    /// old), if any grew, and that span in whole minutes.
    func topGrower(_ samples: [ProcessSample], now: Double) -> (identity: ProcessIdentity, growth: UInt64, minutes: Int)? {
        samples.compactMap { s -> (ProcessIdentity, UInt64, Int)? in
            guard let points = processes[s.identity]?.minutes, !points.isEmpty else { return nil }
            let base = points[max(0, points.count - 1 - L.causeMinutes)]
            let minutes = Int((now - base.ts) / 60)
            return s.mem > base.mem && minutes >= 1 ? (s.identity, s.mem - base.mem, minutes) : nil
        }.max { $0.1 < $1.1 }
    }

    /// The ring's mean on the tick a spell alerts: the ring is full, its mean and median are over the threshold
    /// (most of the window, not a short burst), the spell has not alerted, and `cpuRearm` has passed since the
    /// app's last alert. The spell ends when the ring is no longer over.
    private static func cpuAlert(_ sum: Double, _ state: inout App, lastAlert: Double?, now: Double,
                                 rule: AlertRules.SustainedCPU) -> Double? {
        let count = rule.minutes * 60 / Int(AMX.tick)
        state.sums.push(sum, limit: count)
        guard rule.enabled, state.sums.count == count else { return nil }
        let mean = state.sums.reduce(0, +) / Double(count)
        guard mean > rule.percent, state.sums.sorted()[(count - 1) / 2] > rule.percent else {
            state.alerted = false
            return nil
        }
        guard !state.alerted, lastAlert.map({ now - $0 >= L.cpuRearm }) ?? true else { return nil }
        state.alerted = true
        return mean
    }

    private static func memory(_ s: ProcessSample, _ entry: (name: String, app: AppInfo), _ state: inout Process,
                               now: Double, rules: AlertRules) -> [EventDraft] {
        var out: [EventDraft] = []
        let minute = Int((now / 60).rounded(.down))
        if state.minute != minute {
            state.minute = minute
            state.minutes.push((now, s.mem), limit: rules.memoryGrowth.minutes + 1)
            if let draft = growth(s.identity, entry, &state, rule: rules.memoryGrowth, now: now) { out.append(draft) }
        }
        if now >= state.quietUntil {
            state.ticks.push(s.mem, limit: L.jumpTicks)
            if let draft = jump(s.identity, entry, &state, rule: rules.memoryJump, now: now) { out.append(draft) }
        }
        return out
    }

    /// Steady (least-squares r² ≥ `growthRSquared`) and still growing over the whole window; once per process.
    private static func growth(_ identity: ProcessIdentity, _ entry: (name: String, app: AppInfo), _ state: inout Process,
                               rule: AlertRules.MemoryGrowth, now: Double) -> EventDraft? {
        let points = state.minutes.map(\.mem)
        guard rule.enabled, !state.grew, points.count == rule.minutes + 1, let first = points.first,
              let last = points.last, last >= first + (UInt64(rule.megabytes) << 20),
              last > points[points.count - 1 - L.stillGrowingMinutes],
              case let fit = fit(points), fit.slope > 0, fit.rSquared >= L.growthRSquared else { return nil }
        state.grew = true
        return EventDraft(ts: now, kind: EventKind.alert, severity: 1, identity: identity, rule: RuleName.memoryGrowth,
                          message: "\(EventEngine.who(entry)) grew by \(EventEngine.bytes(last - first)) in \(rule.minutes) min",
                          value: Double(last - first))
    }

    /// A clean step (every later tick above every earlier one) between the two halves of the ring.
    private static func jump(_ identity: ProcessIdentity, _ entry: (name: String, app: AppInfo), _ state: inout Process,
                             rule: AlertRules.MemoryJump, now: Double) -> EventDraft? {
        let half = L.jumpTicks / 2
        guard rule.enabled, state.ticks.count == L.jumpTicks else { return nil }
        let before = state.ticks.prefix(half), after = state.ticks.suffix(half)
        guard let low = before.max(), let high = after.min(), high > low else { return nil }
        let step = after.reduce(0, +) / UInt64(half) - before.reduce(0, +) / UInt64(half)
        guard step >= UInt64(rule.megabytes) << 20 else { return nil }
        state.ticks = []
        state.quietUntil = now + L.jumpQuiet
        return EventDraft(ts: now, kind: EventKind.alert, severity: 1, identity: identity, rule: RuleName.memoryJump,
                          message: "\(EventEngine.who(entry)) jumped by \(EventEngine.bytes(step))", value: Double(step))
    }

    /// Ordinary least squares over evenly spaced points, with r² (1 for a flat line).
    private static func fit(_ ys: [UInt64]) -> (slope: Double, rSquared: Double) {
        let n = Double(ys.count)
        let meanX = (n - 1) / 2
        let meanY = ys.reduce(0.0) { $0 + Double($1) } / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for (i, y) in ys.enumerated() {
            let dx = Double(i) - meanX, dy = Double(y) - meanY
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        return (sxy / sxx, syy > 0 ? sxy * sxy / (sxx * syy) : 1)
    }
}

private extension Array {
    /// Appends and drops the oldest elements beyond `limit`.
    mutating func push(_ element: Element, limit: Int) {
        append(element)
        if count > limit { removeFirst(count - limit) }
    }
}
