import AMXCore
import SwiftUI

/// One app's alert rules (spec §9): mute it, or give a process rule its own values in place of those in Settings. A
/// change applies at once, as in Settings; an app with nothing of its own left has no entry.
struct AppRulesSheet: View {
    let app: AppKey
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private typealias R = AlertRules
    private enum Mode: Hashable { case global, own, off }

    var body: some View {
        let muted = model.settings?.rules.apps[app.key]?.muted ?? false
        let machine = Machine.current, cores = Double(machine.cores), cpuRange = R.SustainedCPU.percentRange(machine)
        VStack(spacing: 0) {
            Form {
                DaemonProblem()
                Group {
                    Section {
                        Toggle("Mute alerts for this app", isOn: entry(\.muted))
                    } footer: {
                        Text("\(app.name) gets no app or process alerts. Memory pressure alerts can still name it.")
                    }
                    Group {
                        rule(RuleName.title(RuleName.sustainedCPU), \.sustainedCPU, \.sustainedCPU, enabled: \.enabled) { r in
                            // Stored of one core; shown as a share of all cores, as in Settings.
                            let shown = (r.wrappedValue.percent / cores * 10).rounded() / 10
                            NumberRow(title: "Above",
                                      value: Binding(get: { shown }, set: { if $0 != shown { r.wrappedValue.percent = $0 * cores } }),
                                      range: ((cpuRange.lowerBound / cores * 10).rounded(.up) / 10)...min(100, cpuRange.upperBound / cores),
                                      step: 1, unit: "% of all cores", format: .number.precision(.fractionLength(0...1)))
                            NumberRow(title: "For", value: r.minutes, range: R.SustainedCPU.minutesRange, unit: "min")
                        }
                        rule(RuleName.title(RuleName.memoryGrowth), \.memoryGrowth, \.memoryGrowth, enabled: \.enabled) { r in
                            NumberRow(title: "Grows by", value: r.megabytes, range: R.MemoryGrowth.megabytesRange(machine),
                                      step: 50, unit: "MB")
                            NumberRow(title: "Over", value: r.minutes, range: R.MemoryGrowth.minutesRange, step: 5, unit: "min")
                        }
                        rule(RuleName.title(RuleName.memoryJump), \.memoryJump, \.memoryJump, enabled: \.enabled) { r in
                            NumberRow(title: "Grows by", value: r.megabytes, range: R.MemoryJump.megabytesRange(machine),
                                      step: 128, unit: "MB")
                        }
                        rule(RuleName.title(RuleName.diskWrites), \.diskWrites, \.diskWrites, enabled: \.enabled) { r in
                            NumberRow(title: "Above", value: units(r.bytesPerHour, 1 << 30),
                                      range: units(R.DiskWrites.bytesPerHourRange, 1 << 30), unit: "GB per hour")
                        }
                        rule(RuleName.title(RuleName.network), \.network, \.network, enabled: \.enabled) { r in
                            NumberRow(title: "Above", value: units(r.bytesPerSecond, 1 << 20),
                                      range: units(R.Network.bytesPerSecondRange, 1 << 20), unit: "MB/s")
                            NumberRow(title: "For", value: r.minutes, range: R.Network.minutesRange, unit: "min")
                        }
                        rule(RuleName.title(RuleName.energy), \.energy, \.energy, enabled: \.enabled) { r in
                            NumberRow(title: "Above", value: r.impact, range: R.Energy.impactRange, step: 50, unit: "impact")
                            NumberRow(title: "For", value: r.minutes, range: R.Energy.minutesRange, unit: "min")
                        }
                        rule(RuleName.title(RuleName.gpu), \.gpu, \.gpu, enabled: \.enabled) { r in
                            NumberRow(title: "Above", value: r.percent, range: R.GPU.percentRange, step: 5, unit: "%")
                            NumberRow(title: "For", value: r.minutes, range: R.GPU.minutesRange, unit: "min")
                        }
                    }
                    .disabled(muted)
                }
                .disabled(model.settings == nil)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).help("Close the alert rules")
            }
            .padding()
        }
        .frame(width: 480, height: 600)
        .task { await model.load() }
    }

    /// A value of this app's entry; a change is applied, and an entry left with nothing of its own is removed.
    private func entry<V: Equatable>(_ path: WritableKeyPath<R.AppOverride, V>) -> Binding<V> {
        Binding(get: { (model.settings?.rules.apps[app.key] ?? R.AppOverride())[keyPath: path] },
                set: { value in
                    Task {
                        await model.apply {
                            var own = $0.rules.apps[app.key] ?? R.AppOverride()
                            own[keyPath: path] = value
                            $0.rules.apps[app.key] = own == R.AppOverride() ? nil : own
                        }
                    }
                })
    }

    /// A rule as in Settings, or with this app's own values, or off for this app. Its rows show the values that apply.
    private func rule<Rule: Equatable>(_ title: String, _ global: KeyPath<AlertRules, Rule>,
                                       _ own: WritableKeyPath<R.AppOverride, Rule?>, enabled: WritableKeyPath<Rule, Bool>,
                                       @ViewBuilder rows: (Binding<Rule>) -> some View) -> some View {
        let stored = entry(own)
        let fallback = (model.settings ?? DaemonSettings()).rules[keyPath: global]
        let value = Binding(get: { stored.wrappedValue ?? fallback }, set: { stored.wrappedValue = $0 })
        let mode: Mode = stored.wrappedValue.map { $0[keyPath: enabled] ? .own : .off } ?? .global
        return Section {
            Picker(title, selection: Binding(get: { mode }, set: { new in
                if new == .global {
                    stored.wrappedValue = nil
                } else {
                    var r = value.wrappedValue
                    r[keyPath: enabled] = new == .own
                    stored.wrappedValue = r
                }
            })) {
                Text("As in Settings").tag(Mode.global)
                Text("Own Values").tag(Mode.own)
                Text("Off").tag(Mode.off)
            }
            .help("Use the \(title) values in Settings, values for this app only, or no \(title) alerts for this app")
            rows(value).disabled(mode != .own)
        }
    }

    /// A byte value in whole `unit`s (GB or MB); a typed value too large for bytes is clamped, so validation rejects it.
    private func units(_ bytes: Binding<Int64>, _ unit: Int64) -> Binding<Int> {
        let limit = Int64.max / unit
        return Binding(get: { Int(bytes.wrappedValue / unit) }, set: { bytes.wrappedValue = min(max(Int64($0), -limit), limit) * unit })
    }

    private func units(_ range: ClosedRange<Int64>, _ unit: Int64) -> ClosedRange<Int> {
        Int(range.lowerBound / unit)...Int(range.upperBound / unit)
    }
}

