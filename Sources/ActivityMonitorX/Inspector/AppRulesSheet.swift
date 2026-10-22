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
        let machine = Machine.current
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
                        rule(RuleName.title(RuleName.sustainedCPU), \.sustainedCPU, \.sustainedCPU, enabled: \.enabled) {
                            AlertRuleRows.sustainedCPU($0, machine)
                        }
                        rule(RuleName.title(RuleName.memoryGrowth), \.memoryGrowth, \.memoryGrowth, enabled: \.enabled) {
                            AlertRuleRows.memoryGrowth($0, machine)
                        }
                        rule(RuleName.title(RuleName.memoryJump), \.memoryJump, \.memoryJump, enabled: \.enabled) {
                            AlertRuleRows.memoryJump($0, machine)
                        }
                        rule(RuleName.title(RuleName.diskWrites), \.diskWrites, \.diskWrites, enabled: \.enabled, rows: AlertRuleRows.diskWrites)
                        rule(RuleName.title(RuleName.network), \.network, \.network, enabled: \.enabled, rows: AlertRuleRows.network)
                        rule(RuleName.title(RuleName.energy), \.energy, \.energy, enabled: \.enabled, rows: AlertRuleRows.energy)
                        rule(RuleName.title(RuleName.gpu), \.gpu, \.gpu, enabled: \.enabled, rows: AlertRuleRows.gpu)
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
}

