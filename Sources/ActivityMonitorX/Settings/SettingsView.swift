import AMXCore
import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// The Settings scene (spec §8): app choices, alert rules, recording and the helper's status. Daemon-backed controls
/// change `amxd`'s settings over XPC (M4-D1).
struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"
    @Environment(SettingsModel.self) private var model
    @Environment(Preferences.self) private var preferences
    @Environment(Notifier.self) private var notifier: Notifier?
    @Environment(\.controlActiveState) private var active

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") { GeneralSettings() }
            Tab("Alerts", systemImage: "bell.badge", value: "alerts") { AlertSettings() }
            Tab("Recording", systemImage: "internaldrive", value: "recording") { RecordingSettings() }
            Tab("Helper", systemImage: "wrench.and.screwdriver", value: "helper") { HelperSettings() }
        }
        .frame(width: 520, height: 600)
        // Login Items, notification permission and the helper can all change while the window is in the background.
        .onChange(of: active == .key, initial: true) { _, key in
            guard key else { return }
            preferences.refreshLogin()
            Task {
                await notifier?.refreshStatus()
                await model.load()
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Notifier.self) private var notifier: Notifier?

    var body: some View {
        let prefs = Bindable(preferences)
        Form {
            Section {
                Toggle("Launch at Login", isOn: prefs.launchAtLogin)
                if preferences.loginNeedsApproval {
                    LabeledContent("Needs approval") {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            } footer: {
                if let error = preferences.loginError { Text(error) }
            }
            Section {
                Toggle("Show in Menu Bar", isOn: prefs.menuBarShown)
            } footer: {
                Text("While it is shown, closing the window keeps Activity Monitor X running, so new alerts still notify.")
            }
            Section {
                if let notifier, [.authorized, .provisional].contains(notifier.status) {
                    LabeledContent("Notifications", value: "On")
                } else {
                    LabeledContent("Notifications are off") {
                        Button("Open Notification Settings") {
                            let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(AMX.bundleID)"
                            NSWorkspace.shared.open(URL(string: url)!)
                        }
                    }
                }
            } footer: {
                Text("One notification per new alert while Activity Monitor X runs.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        let rules = (model.settings ?? DaemonSettings()).rules
        let percent = model.binding(\.rules.sustainedCPU.percent)
        Form {
            DaemonProblem()
            Group {
                Section {
                    Toggle("Sustained CPU", isOn: model.binding(\.rules.sustainedCPU.enabled))
                    Group {
                        NumberRow(title: "Above", value: Binding(get: { Int(percent.wrappedValue.rounded()) },
                                                                 set: { percent.wrappedValue = Double($0) }),
                                  range: Int(AlertRules.SustainedCPU.percentRange.lowerBound)...Int(AlertRules.SustainedCPU.percentRange.upperBound),
                                  step: 10, unit: "% of one core")
                        NumberRow(title: "For", value: model.binding(\.rules.sustainedCPU.minutes),
                                  range: AlertRules.SustainedCPU.minutesRange, unit: "min")
                    }
                    .disabled(!rules.sustainedCPU.enabled)
                } footer: {
                    Text("An app stays above this CPU for this long. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle("Memory Growth", isOn: model.binding(\.rules.memoryGrowth.enabled))
                    Group {
                        NumberRow(title: "Grows by", value: model.binding(\.rules.memoryGrowth.megabytes),
                                  range: AlertRules.MemoryGrowth.megabytesRange, step: 50, unit: "MB")
                        NumberRow(title: "Over", value: model.binding(\.rules.memoryGrowth.minutes),
                                  range: AlertRules.MemoryGrowth.minutesRange, step: 5, unit: "min")
                    }
                    .disabled(!rules.memoryGrowth.enabled)
                } footer: {
                    Text("A process grows steadily by this much over this time. Once per process.")
                }
                Section {
                    Toggle("Memory Jump", isOn: model.binding(\.rules.memoryJump.enabled))
                    NumberRow(title: "Grows by", value: model.binding(\.rules.memoryJump.megabytes),
                              range: AlertRules.MemoryJump.megabytesRange, step: 256, unit: "MB")
                        .disabled(!rules.memoryJump.enabled)
                } footer: {
                    Text("A process grows by this much in under a minute. Then it is quiet for 30 min.")
                }
                Section {
                    Toggle("Memory Pressure", isOn: model.binding(\.rules.pressure.enabled))
                    Picker("At", selection: model.binding(\.rules.pressure.level)) {
                        ForEach(AlertRules.Pressure.Level.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .disabled(!rules.pressure.enabled)
                } footer: {
                    Text("Memory pressure reaches this level. At most once per 10 min.")
                }
                Section {
                    Toggle("Sustained Thermal State", isOn: model.binding(\.rules.thermal.enabled))
                    Group {
                        Picker("At or above", selection: model.binding(\.rules.thermal.state)) {
                            ForEach(AlertRules.Thermal.State.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        NumberRow(title: "For", value: model.binding(\.rules.thermal.minutes),
                                  range: AlertRules.Thermal.minutesRange, unit: "min")
                    }
                    .disabled(!rules.thermal.enabled)
                } footer: {
                    Text("The Mac stays at or above this thermal state for this long.")
                }
            }
            .disabled(model.settings == nil)
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettings: View {
    @Environment(SettingsModel.self) private var model
    /// A lower cap waits for confirmation: the next rollup deletes the history beyond it.
    private let _lowerCap = State<Int64?>(initialValue: nil)

    var body: some View {
        let settings = model.settings ?? DaemonSettings()
        let cap = settings.sizeCapBytes
        Form {
            DaemonProblem()
            Group {
                Section {
                    Picker("Size Cap", selection: Binding(get: { cap }, set: { new in
                        if new < cap { _lowerCap.wrappedValue = new } else { Task { await model.apply { $0.sizeCapBytes = new } } }
                    })) {
                        // A cap set outside these choices stays selectable, so the picker is never blank.
                        ForEach(DaemonSettings.sizeCapChoices.contains(cap) ? [] : [cap], id: \.self) { Text(gigabytes($0)).tag($0) }
                        ForEach(DaemonSettings.sizeCapChoices, id: \.self) { Text(gigabytes($0)).tag($0) }
                    }
                } footer: {
                    Text("Past the cap, the oldest history is deleted first.")
                }
                Section {
                    ForEach(settings.terminalBundleIDs, id: \.self) { id in
                        HStack {
                            Text(id)
                            Spacer()
                            Button("Remove \(id)", systemImage: "minus.circle") {
                                Task { await model.apply { $0.terminalBundleIDs.removeAll { $0 == id } } }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add App…", systemImage: "plus") { addTerminal() }
                } header: {
                    Text("Terminal Apps")
                } footer: {
                    Text("Programs started in these apps count as their own app, not the terminal. Applies to processes that start after the change.")
                }
            }
            .disabled(model.settings == nil)
        }
        .formStyle(.grouped)
        .alert("Lower the Size Cap?",
               isPresented: Binding(get: { _lowerCap.wrappedValue != nil }, set: { if !$0 { _lowerCap.wrappedValue = nil } }),
               presenting: _lowerCap.wrappedValue) { new in
            Button("Lower to \(gigabytes(new))", role: .destructive) { Task { await model.apply { $0.sizeCapBytes = new } } }
            Button("Cancel", role: .cancel) {}
        } message: { new in
            Text("Older history beyond \(gigabytes(new)) will be deleted within a minute.")
        }
    }

    private func gigabytes(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file)) }

    private func addTerminal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.apply { try $0.addTerminal(appAt: url) } }
    }
}

private struct HelperSettings: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        let ping = model.ping
        let current = ping.map { $0.version >= DaemonPing.protocolVersion } ?? false
        Form {
            Section {
                LabeledContent("Status", value: ping == nil ? "Not reachable" : current ? "Running" : "Out of date")
                if let ping {
                    LabeledContent("Protocol Version", value: String(ping.version))
                    LabeledContent("Uptime", value: Duration.seconds(ping.uptime)
                        .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)))
                    LabeledContent("Database") {
                        Text(ping.db).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    LabeledContent("PID", value: String(ping.pid))
                }
            }
            if !current {
                Section {
                    Text("make install").font(.body.monospaced()).textSelection(.enabled)
                } header: {
                    Text("Install Command")
                } footer: {
                    Text("Run it in the Activity Monitor X repository. It asks for an administrator password and restarts the helper.")
                }
            }
            Section {
                Button("Check Again") { Task { await model.load() } }
            }
        }
        .formStyle(.grouped)
    }
}

/// Why the daemon-backed controls are disabled, or why the last change was not applied.
private struct DaemonProblem: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        if let error = model.error {
            Section {
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            }
        }
    }
}

/// A whole number with its unit, typed or stepped.
private struct NumberRow: View {
    let title: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text(unit).foregroundStyle(.secondary)
                Stepper(title, value: value, in: range, step: step).labelsHidden()
            }
        }
    }
}

extension SettingsModel {
    /// A control's value: the defaults while `settings` is nil (the control is disabled then); a change is applied.
    func binding<V>(_ path: WritableKeyPath<DaemonSettings, V>) -> Binding<V> {
        Binding(get: { (self.settings ?? DaemonSettings())[keyPath: path] },
                set: { value in Task { await self.apply { $0[keyPath: path] = value } } })
    }
}
