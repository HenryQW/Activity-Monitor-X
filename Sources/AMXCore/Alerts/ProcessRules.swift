// MIT License. See Packaging/Credits.html.
import Foundation

/// Per-app rules (sustained CPU, disk writes, network, energy, GPU) and per-process memory growth and jump. Pure;
/// rings and spells live only for the processes and apps of the current tick (a total rule keeps an app while its
/// hour holds bytes) and only while a ring is not all zero; an app's last alert time per rule lives for
/// `AlertLimits.appRearm`.
struct ProcessRules: Sendable {
    private typealias L = AlertLimits

    private struct Key: Hashable {
        let rule: String
        let app: String
    }

    private struct Spell {
        /// The app's name and its process that added most on the last tick it added anything, for an alert after
        /// its processes ended.
        var name = ""
        var busiest: ProcessIdentity?
        /// The app's sum per tick, or per minute for a total rule.
        var sums: [Double] = []
        var minute: Int?
        /// The current spell over the threshold has alerted.
        var alerted = false
    }

    /// A per-app rule over the sum of its processes' `value` per tick.
    private struct AppRule {
        let name: String
        let enabled: Bool
        let threshold: Double
        /// The ring's length: ticks for a held rule, minutes for a total rule.
        let length: Int
        /// The ring's total reaches the threshold (disk writes), else its mean and median do.
        let total: Bool
        let value: (ProcessSample) -> Double
        let message: (_ app: String, _ value: Double) -> String
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

    private var spells: [Key: Spell] = [:]
    private var processes: [ProcessIdentity: Process] = [:]
    /// Kept when the app's processes end, so a restarted app does not alert again at once.
    private var lastAlert: [Key: Double] = [:]

    /// After a sleep every spell starts again, but the per-app re-arm and the grown processes keep counting (M4-D5).
    mutating func restartSpells() {
        let kept = lastAlert, grown = processes.filter(\.value.grew)
        self = ProcessRules()
        lastAlert = kept
        processes = grown.mapValues { _ in
            var p = Process()
            p.grew = true
            return p
        }
    }

    var watchedProcesses: Int { processes.count }
    var watchedApps: Int { Set(spells.keys.map(\.app)).count }

    /// `kernel_task` is skipped: its CPU is thermal management.
    mutating func evaluate(now: Double, samples: [ProcessSample], known: [ProcessIdentity: (name: String, app: AppInfo)],
                           rules: AlertRules) -> [EventDraft] {
        var out: [EventDraft] = []
        var liveProcesses: [ProcessIdentity: Process] = [:]
        var tick: [String: (name: String, samples: [ProcessSample])] = [:]
        // An app with its own rules (or muted) uses them in place of the global ones.
        let perApp = Dictionary(uniqueKeysWithValues: rules.apps.keys.map { ($0, rules.forApp($0)) })
        for s in samples {
            guard let entry = known[s.identity], entry.name != "kernel_task" else { continue }
            let (name, app) = entry
            let key = app.appPath ?? name
            var state = processes.removeValue(forKey: s.identity) ?? Process()
            out += Self.memory(s, entry, &state, now: now, rules: perApp[key] ?? rules)
            liveProcesses[s.identity] = state
            tick[key, default: (app.appName, [])].samples.append(s)
        }
        processes = liveProcesses

        lastAlert = lastAlert.filter { now - $0.value < L.appRearm }
        var liveSpells: [Key: Spell] = [:]
        let perAppRules = perApp.mapValues(Self.appRules)
        for (i, global) in Self.appRules(rules).enumerated() {
            // A total rule keeps an app with no process this tick: it adds 0 until its hour is empty.
            let kept = global.total ? spells.keys.filter { $0.rule == global.name }.map(\.app) : []
            for app in Set(tick.keys).union(kept) {
                let rule = perAppRules[app]?[i] ?? global
                let key = Key(rule: rule.name, app: app)
                var state = spells.removeValue(forKey: key) ?? Spell()
                let samples = tick[app]?.samples ?? []
                if let t = tick[app] { state.name = t.name }
                if let top = samples.max(by: { rule.value($0) < rule.value($1) }), rule.value(top) > 0 {
                    state.busiest = top.identity
                }
                if let value = Self.appAlert(samples.reduce(0) { $0 + rule.value($1) }, &state, lastAlert: lastAlert[key],
                                             now: now, rule: rule) {
                    lastAlert[key] = now
                    out.append(EventDraft(ts: now, kind: EventKind.alert, severity: 1, identity: state.busiest,
                                          rule: rule.name, message: rule.message(state.name, value), value: value))
                }
                if state.sums.contains(where: { $0 != 0 }) { liveSpells[key] = state }
            }
        }
        spells = liveSpells
        return out
    }

    private static func appRules(_ r: AlertRules) -> [AppRule] {
        func ticks(_ minutes: Int) -> Int { minutes * 60 / Int(AMX.tick) }
        let cpu = r.sustainedCPU, disk = r.diskWrites, net = r.network, energy = r.energy, gpu = r.gpu
        return [
            AppRule(name: RuleName.sustainedCPU, enabled: cpu.enabled, threshold: cpu.percent, length: ticks(cpu.minutes),
                    total: false, value: \.cpu) { "\($0) used \(Int($1.rounded())) % CPU for \(cpu.minutes) min" },
            AppRule(name: RuleName.diskWrites, enabled: disk.enabled, threshold: Double(disk.bytesPerHour), length: 60,
                    total: true, value: { $0.diskW * AMX.tick }) { "\($0) wrote \(EventEngine.bytes(UInt64($1))) in 1 hour" },
            AppRule(name: RuleName.network, enabled: net.enabled, threshold: Double(net.bytesPerSecond), length: ticks(net.minutes),
                    total: false, value: { $0.netIn + $0.netOut }) {
                "\($0) received and sent \(EventEngine.bytes(UInt64($1)))/s for \(net.minutes) min"
            },
            AppRule(name: RuleName.energy, enabled: energy.enabled, threshold: Double(energy.impact), length: ticks(energy.minutes),
                    total: false, value: \.energy) { "\($0) had energy impact \(Int($1.rounded())) for \(energy.minutes) min" },
            AppRule(name: RuleName.gpu, enabled: gpu.enabled, threshold: Double(gpu.percent), length: ticks(gpu.minutes),
                    total: false, value: \.gpu) { "\($0) used \(Int($1.rounded())) % GPU for \(gpu.minutes) min" },
        ]
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

    /// The ring's value on the tick a spell alerts. A held rule needs a full ring whose mean and median reach the
    /// threshold (most of the window, not a short burst) and gives the mean; a total rule needs the total of its
    /// minutes (this one and the 59 before) to reach it and gives the total. The spell must not have alerted, and
    /// `appRearm` must have passed since the app's last alert of the rule. The spell ends when the ring no longer
    /// reaches the threshold.
    private static func appAlert(_ sum: Double, _ state: inout Spell, lastAlert: Double?, now: Double,
                                 rule: AppRule) -> Double? {
        let minute = Int((now / 60).rounded(.down))
        if rule.total, state.minute == minute {
            state.sums[state.sums.count - 1] += sum
        } else {
            state.sums.push(sum, limit: rule.length)
        }
        state.minute = minute
        guard rule.enabled, rule.total || state.sums.count == rule.length else { return nil }
        let total = state.sums.reduce(0, +), value = rule.total ? total : total / Double(rule.length)
        guard value >= rule.threshold, rule.total || state.sums.sorted()[(rule.length - 1) / 2] >= rule.threshold else {
            state.alerted = false
            return nil
        }
        guard !state.alerted, lastAlert.map({ now - $0 >= L.appRearm }) ?? true else { return nil }
        state.alerted = true
        return value
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
