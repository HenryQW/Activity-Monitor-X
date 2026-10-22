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
                Picker("Appearance", selection: prefs.appearance) {
                    Text("System").tag(Preferences.Appearance.system)
                    Text("Light").tag(Preferences.Appearance.light)
                    Text("Dark").tag(Preferences.Appearance.dark)
                }
                .help("Follow the macOS light or dark setting, or always use one")
                Picker("Open at", selection: prefs.openAt) {
                    ForEach(StartScreen.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .help("Choose the screen the main window opens at")
                Picker("Time range at open", selection: prefs.openRange) {
                    ForEach(StartRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .help("Choose the time range the main window opens at")
            }
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
                Picker("Menu Bar", selection: prefs.menuBarStyle) {
                    Text("Text only").tag(MenuBarStyle.text)
                    Text("Text + chart").tag(MenuBarStyle.chart)
                }
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

    private typealias R = AlertRules

    var body: some View {
        let rules = (model.settings ?? DaemonSettings()).rules
        let machine = Machine.current, cores = Double(machine.cores)
        let percent = model.binding(\.rules.sustainedCPU.percent), cpuRange = R.SustainedCPU.percentRange(machine)
        Form {
            DaemonProblem()
            Group {
                Section {
                    Picker("Preset", selection: Binding(get: { rules.preset }, set: { preset in
                        Task {
                            await model.apply {
                                if preset == .custom {
                                    $0.rules.preset = .custom
                                } else {
                                    $0.rules = .make(preset, for: machine, keepingSwitchesOf: $0.rules)
                                }
                            }
                        }
                    })) {
                        ForEach(AlertPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                } footer: {
                    Text("Relaxed, Balanced and Strict set the values of every rule below for this Mac's cores and memory, and keep each rule on or off. A change to a value makes it Custom.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.sustainedCPU), isOn: model.binding(\.rules.sustainedCPU.enabled, custom: false))
                    Group {
                        // Stored of one core; shown as a share of all cores. Only a value other than the shown one is
                        // stored, so showing never changes it.
                        NumberRow(title: "Above", value: Binding(get: { Self.share(percent.wrappedValue, cores) },
                                                                 set: { if $0 != Self.share(percent.wrappedValue, cores) { percent.wrappedValue = $0 * cores } }),
                                  range: ((cpuRange.lowerBound / cores * 10).rounded(.up) / 10)...min(100, cpuRange.upperBound / cores),
                                  step: 1, unit: "% of all cores", format: .number.precision(.fractionLength(0...1)))
                        NumberRow(title: "For", value: model.binding(\.rules.sustainedCPU.minutes),
                                  range: R.SustainedCPU.minutesRange, unit: "min")
                    }
                    .disabled(!rules.sustainedCPU.enabled)
                } footer: {
                    Text("An app stays above this CPU for this long. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.memoryGrowth), isOn: model.binding(\.rules.memoryGrowth.enabled, custom: false))
                    Group {
                        NumberRow(title: "Grows by", value: model.binding(\.rules.memoryGrowth.megabytes),
                                  range: R.MemoryGrowth.megabytesRange(machine), step: 50, unit: "MB")
                        NumberRow(title: "Over", value: model.binding(\.rules.memoryGrowth.minutes),
                                  range: R.MemoryGrowth.minutesRange, step: 5, unit: "min")
                    }
                    .disabled(!rules.memoryGrowth.enabled)
                } footer: {
                    Text("A process grows steadily by this much over this time. Once per process.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.memoryJump), isOn: model.binding(\.rules.memoryJump.enabled, custom: false))
                    NumberRow(title: "Grows by", value: model.binding(\.rules.memoryJump.megabytes),
                              range: R.MemoryJump.megabytesRange(machine), step: 128, unit: "MB")
                        .disabled(!rules.memoryJump.enabled)
                } footer: {
                    Text("A process grows by this much in under a minute. Then it is quiet for 30 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.pressure), isOn: model.binding(\.rules.pressure.enabled, custom: false))
                    Picker("At", selection: model.binding(\.rules.pressure.level)) {
                        ForEach(AlertRules.Pressure.Level.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .disabled(!rules.pressure.enabled)
                } footer: {
                    Text("Memory pressure reaches this level. At most once per 60 min.")
                }
                Section {
                    Toggle("Sustained Thermal State", isOn: model.binding(\.rules.thermal.enabled, custom: false))
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
                Section {
                    Toggle(RuleName.title(RuleName.diskWrites), isOn: model.binding(\.rules.diskWrites.enabled, custom: false))
                    NumberRow(title: "Above", value: units(\.rules.diskWrites.bytesPerHour, 1 << 30),
                              range: units(R.DiskWrites.bytesPerHourRange, 1 << 30), unit: "GB per hour")
                        .disabled(!rules.diskWrites.enabled)
                } footer: {
                    Text("An app writes this much to disk in one hour. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.network), isOn: model.binding(\.rules.network.enabled, custom: false))
                    Group {
                        NumberRow(title: "Above", value: units(\.rules.network.bytesPerSecond, 1 << 20),
                                  range: units(R.Network.bytesPerSecondRange, 1 << 20), unit: "MB/s")
                        NumberRow(title: "For", value: model.binding(\.rules.network.minutes), range: R.Network.minutesRange, unit: "min")
                    }
                    .disabled(!rules.network.enabled)
                } footer: {
                    Text("An app receives and sends more than this for this long. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.energy), isOn: model.binding(\.rules.energy.enabled, custom: false))
                    Group {
                        NumberRow(title: "Above", value: model.binding(\.rules.energy.impact), range: R.Energy.impactRange,
                                  step: 50, unit: "impact")
                        NumberRow(title: "For", value: model.binding(\.rules.energy.minutes), range: R.Energy.minutesRange, unit: "min")
                    }
                    .disabled(!rules.energy.enabled)
                } footer: {
                    Text("An app stays above this energy impact for this long. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.gpu), isOn: model.binding(\.rules.gpu.enabled, custom: false))
                    Group {
                        NumberRow(title: "Above", value: model.binding(\.rules.gpu.percent), range: R.GPU.percentRange,
                                  step: 5, unit: "%")
                        NumberRow(title: "For", value: model.binding(\.rules.gpu.minutes), range: R.GPU.minutesRange, unit: "min")
                    }
                    .disabled(!rules.gpu.enabled)
                } footer: {
                    Text("An app stays above this GPU use for this long. Then that app is quiet for 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.swap), isOn: model.binding(\.rules.swap.enabled, custom: false))
                    NumberRow(title: "Above", value: model.binding(\.rules.swap.percentOfMemory),
                              range: R.Swap.percentOfMemoryRange, step: 5, unit: "% of RAM")
                        .disabled(!rules.swap.enabled)
                } footer: {
                    Text("Swap reaches this share of memory. At most once per 60 min.")
                }
                Section {
                    Toggle(RuleName.title(RuleName.freeSpace), isOn: model.binding(\.rules.freeSpace.enabled, custom: false))
                    NumberRow(title: "Below", value: model.binding(\.rules.freeSpace.percentFree),
                              range: R.FreeSpace.percentFreeRange, unit: "% free")
                        .disabled(!rules.freeSpace.enabled)
                } footer: {
                    Text("Free space on the startup disk falls to this share. At most once per 24 h.")
                }
            }
            .disabled(model.settings == nil)
        }
        .formStyle(.grouped)
    }

    /// CPU % of one core as % of all cores, to one decimal.
    private static func share(_ percent: Double, _ cores: Double) -> Double { (percent / cores * 10).rounded() / 10 }

    /// A byte value in whole `unit`s (GB or MB); a typed value too large for bytes is clamped, so validation rejects it.
    private func units(_ path: WritableKeyPath<DaemonSettings, Int64>, _ unit: Int64) -> Binding<Int> {
        let bytes = model.binding(path)
        let limit = Int64.max / unit
        return Binding(get: { Int(bytes.wrappedValue / unit) }, set: { bytes.wrappedValue = min(max(Int64($0), -limit), limit) * unit })
    }

    private func units(_ range: ClosedRange<Int64>, _ unit: Int64) -> ClosedRange<Int> {
        Int(range.lowerBound / unit)...Int(range.upperBound / unit)
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
                            .help("Remove this app from the list")
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
struct DaemonProblem: View {
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

/// A number with its unit, typed or stepped.
struct NumberRow<F: ParseableFormatStyle>: View where F.FormatOutput == String, F.FormatInput: Strideable {
    let title: String
    let value: Binding<F.FormatInput>
    let range: ClosedRange<F.FormatInput>
    let step: F.FormatInput.Stride
    let unit: String
    let format: F

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: format)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text(unit).foregroundStyle(.secondary)
                Stepper(title, value: value, in: range, step: step).labelsHidden()
                    .help(Text(verbatim: "\(title) \(range.lowerBound) to \(range.upperBound) \(unit), in steps of \(step)"))
            }
        }
    }
}

extension NumberRow where F == IntegerFormatStyle<Int> {
    /// A whole number.
    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, unit: String) {
        self.init(title: title, value: value, range: range, step: step, unit: unit, format: .number)
    }
}

extension SettingsModel {
    /// A rule control's value: the defaults while `settings` is nil (the control is disabled then); a change is
    /// applied, and a changed value (`custom`, not an on/off switch, which presets keep) makes the preset Custom.
    func binding<V: Equatable>(_ path: WritableKeyPath<DaemonSettings, V>, custom: Bool = true) -> Binding<V> {
        Binding(get: { (self.settings ?? DaemonSettings())[keyPath: path] },
                set: { value in
                    Task {
                        await self.apply {
                            guard $0[keyPath: path] != value else { return }
                            $0[keyPath: path] = value
                            if custom { $0.rules.preset = .custom }
                        }
                    }
                })
    }
}
