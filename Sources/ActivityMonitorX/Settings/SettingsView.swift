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
    @AppStorage(TerminalApp.key) private var terminal = TerminalApp.defaultID

    private static func weekday(_ number: Int) -> String { Calendar.autoupdatingCurrent.weekdaySymbols[number - 1] }

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
                Picker("Window opens with", selection: prefs.openAt) {
                    ForEach(StartScreen.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .help("Choose the screen the main window opens with")
                Picker("Time range at open", selection: prefs.openRange) {
                    ForEach(StartRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .help("Choose the time range the main window opens at")
                Picker("First day of week", selection: prefs.firstWeekday) {
                    Text("Follow System (\(Self.weekday(Calendar.autoupdatingCurrent.firstWeekday)))").tag(Int?.none)
                    Divider()
                    ForEach(1...7, id: \.self) { Text(Self.weekday($0)).tag(Optional($0)) }
                }
                .help("Choose the day each week starts on in the Calendar. Follow System uses the Language and Region setting.")
                Picker("Terminal", selection: $terminal) {
                    ForEach(TerminalApp.installed, id: \.id) { Text($0.name).tag($0.id) }
                }
                .help("Choose the app that Open in Terminal uses in the Disk Space menu")
            }
            Section {
                Toggle("Launch at login", isOn: prefs.launchAtLogin)
                    .help("Open Activity Monitor X when you log in")
                if preferences.loginNeedsApproval {
                    LabeledContent("Needs approval") {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                            .help("Open Login Items in System Settings to approve the app")
                    }
                }
            } footer: {
                if let error = preferences.loginError { Text(error) }
            }
            Section {
                Toggle("Show in menu bar", isOn: prefs.menuBarShown)
                    .help("Show CPU and memory pressure in the menu bar")
                Picker("Menu bar colours", selection: prefs.menuBarColor) {
                    Text("Colour").tag(true)
                    Text("Greyscale").tag(false)
                }
                .disabled(!preferences.menuBarShown)
                .help("Show warning and critical numbers in yellow and red, or keep the item in the menu bar's own colour")
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
                        .help("Open the app's notification settings in System Settings")
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
    @AppStorage(Notifier.criticalBannersOnlyKey) private var criticalBannersOnly = true

    private typealias R = AlertRules

    var body: some View {
        let rules = (model.settings ?? DaemonSettings()).rules
        let machine = Machine.current
        Form {
            Section {
                Picker("Banners for", selection: $criticalBannersOnly) {
                    Text("All Alerts").tag(false)
                    Text("Critical Only").tag(true)
                }
                .help("Choose which alerts show a banner. The other alerts go to Notification Center only.")
            } header: {
                Text("Notifications")
            } footer: {
                Text(criticalBannersOnly ? "Warnings go to Notification Center without a banner." : "Every alert shows a banner.")
            }
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
                    .help("Set the values of every rule below")
                } footer: {
                    Text("Relaxed, Balanced and Strict set the values of every rule below for this Mac's cores and memory, and keep each rule on or off. A change to a value makes it Custom.")
                }
                ForEach([("App Rules", true), ("System Rules", false)], id: \.0) { title, app in
                    Section(title) {
                        ForEach(specs(rules, machine).filter { RuleName.system.contains($0.id) != app }) { row($0) }
                    }
                }
            }
            .disabled(model.settings == nil)
        }
        .formStyle(.grouped)
        .sheet(item: _open.projectedValue) { open in
            if let spec = specs(rules, machine).first(where: { $0.id == open.id }) { detail(spec) }
        }
    }

    /// A rule as Settings lists it: what it watches, its values in a few words, its switch, and its value rows and footer
    /// for the sheet.
    private struct Spec: Identifiable {
        let id: String
        let enabled: WritableKeyPath<DaemonSettings, Bool>
        let summary: String
        let footer: String
        let rows: () -> AnyView
    }

    private struct Open: Identifiable { let id: String }

    private let _open = State<Open?>(initialValue: nil)

    private func specs(_ r: AlertRules, _ machine: Machine) -> [Spec] {
        let cores = Double(machine.cores)
        func pct(_ value: Double) -> String { (value / 100).formatted(.percent.precision(.fractionLength(0...1))) }
        return [
            Spec(id: RuleName.sustainedCPU, enabled: \.rules.sustainedCPU.enabled,
                 summary: "\(pct(r.sustainedCPU.percent / cores)) of all cores for \(r.sustainedCPU.minutes) min",
                 footer: "An app stays above this CPU for this long. Then that app is quiet for 60 min.") {
                AnyView(AlertRuleRows.sustainedCPU(model.binding(\.rules.sustainedCPU), machine)) },
            Spec(id: RuleName.memoryGrowth, enabled: \.rules.memoryGrowth.enabled,
                 summary: "\(r.memoryGrowth.megabytes.formatted()) MB in \(r.memoryGrowth.minutes) min",
                 footer: "A process grows steadily by this much over this time. Once per process.") {
                AnyView(AlertRuleRows.memoryGrowth(model.binding(\.rules.memoryGrowth), machine)) },
            Spec(id: RuleName.memoryJump, enabled: \.rules.memoryJump.enabled,
                 summary: "\(r.memoryJump.megabytes.formatted()) MB at once",
                 footer: "A process grows by this much in under a minute. Then it is quiet for 30 min.") {
                AnyView(AlertRuleRows.memoryJump(model.binding(\.rules.memoryJump), machine)) },
            Spec(id: RuleName.diskWrites, enabled: \.rules.diskWrites.enabled,
                 summary: "\((r.diskWrites.bytesPerHour / 1_000_000_000).formatted()) GB per hour",
                 footer: "An app writes this much to disk in one hour. Then that app is quiet for 60 min.") {
                AnyView(AlertRuleRows.diskWrites(model.binding(\.rules.diskWrites))) },
            Spec(id: RuleName.network, enabled: \.rules.network.enabled,
                 summary: "\((r.network.bytesPerSecond / 1_000_000).formatted()) MB/s for \(r.network.minutes) min",
                 footer: "An app receives and sends more than this for this long. Then that app is quiet for 60 min.") {
                AnyView(AlertRuleRows.network(model.binding(\.rules.network))) },
            Spec(id: RuleName.energy, enabled: \.rules.energy.enabled,
                 summary: "\(r.energy.impact.formatted()) impact for \(r.energy.minutes) min",
                 footer: "An app stays above this energy impact for this long. Then that app is quiet for 60 min.") {
                AnyView(AlertRuleRows.energy(model.binding(\.rules.energy))) },
            Spec(id: RuleName.gpu, enabled: \.rules.gpu.enabled,
                 summary: "\(pct(Double(r.gpu.percent))) for \(r.gpu.minutes) min",
                 footer: "An app stays above this GPU use for this long. Then that app is quiet for 60 min.") {
                AnyView(AlertRuleRows.gpu(model.binding(\.rules.gpu))) },
            Spec(id: RuleName.pressure, enabled: \.rules.pressure.enabled,
                 summary: "At \(r.pressure.level.rawValue.capitalized)",
                 footer: "Memory pressure reaches this level. At most once per 60 min.") {
                AnyView(Picker("At", selection: model.binding(\.rules.pressure.level)) {
                    ForEach(AlertRules.Pressure.Level.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }) },
            Spec(id: RuleName.thermal, enabled: \.rules.thermal.enabled,
                 summary: "\(r.thermal.state.rawValue.capitalized) or above for \(r.thermal.minutes) min",
                 footer: "The Mac stays at or above this thermal state for this long.") {
                AnyView(Group {
                    Picker("At or above", selection: model.binding(\.rules.thermal.state)) {
                        ForEach(AlertRules.Thermal.State.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    NumberRow(title: "For", value: model.binding(\.rules.thermal.minutes), range: AlertRules.Thermal.minutesRange, unit: "min")
                }) },
            Spec(id: RuleName.systemCPU, enabled: \.rules.systemCPU.enabled,
                 summary: "\(Units.percent(Double(r.systemCPU.warning))) warning, \(Units.percent(Double(r.systemCPU.critical))) critical, \(r.systemCPU.minutes) min",
                 footer: "The Mac's CPU stays above a level for this long. A new spell alerts at most once per 60 min; a rise to critical alerts again.") {
                AnyView(Group {
                    NumberRow(title: "Warning at", value: model.binding(\.rules.systemCPU.warning),
                              range: R.SystemCPU.percentRange, step: 5, unit: "% of all cores")
                    NumberRow(title: "Critical at", value: model.binding(\.rules.systemCPU.critical),
                              range: R.SystemCPU.percentRange, step: 5, unit: "% of all cores")
                    NumberRow(title: "For", value: model.binding(\.rules.systemCPU.minutes), range: R.SystemCPU.minutesRange, unit: "min")
                }) },
            Spec(id: RuleName.swap, enabled: \.rules.swap.enabled,
                 summary: "Above \(Units.percent(Double(r.swap.percentOfMemory))) of RAM",
                 footer: "Swap reaches this share of memory. At most once per 60 min.") {
                AnyView(NumberRow(title: "Above", value: model.binding(\.rules.swap.percentOfMemory),
                                  range: R.Swap.percentOfMemoryRange, step: 5, unit: "% of RAM")) },
            Spec(id: RuleName.freeSpace, enabled: \.rules.freeSpace.enabled,
                 summary: "Below \(Units.percent(Double(r.freeSpace.percentFree))) free",
                 footer: "Free space on the startup disk falls to this share. At most once per 24 h.") {
                AnyView(NumberRow(title: "Below", value: model.binding(\.rules.freeSpace.percentFree),
                                  range: R.FreeSpace.percentFreeRange, unit: "% free")) },
        ]
    }

    /// As a row in Notifications settings: the symbol of what the rule watches, its name and values, its switch; a click
    /// on the row or its arrow opens the values.
    private func row(_ spec: Spec) -> some View {
        let title = RuleName.title(spec.id)
        return HStack(spacing: Layout.inset) {
            Image(systemName: RuleName.symbol(spec.id)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: Layout.gap) {
                Text(title)
                Text(spec.summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: Layout.inset)
            Toggle(title, isOn: model.binding(spec.enabled, custom: false)).labelsHidden().toggleStyle(.switch)
                .help("Turn the \(title) rule on or off")
            Button("Edit \(title) Values", systemImage: "chevron.right") { _open.wrappedValue = Open(id: spec.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Change the values of \(title)")
        }
        .contentShape(Rectangle())
        .onTapGesture { _open.wrappedValue = Open(id: spec.id) }
        .contextMenu {
            let on = model.binding(spec.enabled, custom: false)
            Group {
                Button(on.wrappedValue ? "Turn Off" : "Turn On", systemImage: on.wrappedValue ? "bell.slash" : "bell") { on.wrappedValue.toggle() }
                    .help(on.wrappedValue ? "Turn off alerts for \(title)" : "Turn on alerts for \(title)")
                Button("Edit Values…", systemImage: "slider.horizontal.3") { _open.wrappedValue = Open(id: spec.id) }
                    .help("Change the values of \(title)")
            }
            .labelStyle(.titleAndIcon)
        }
    }

    /// The rule's switch and values, with the footer that says what it watches.
    private func detail(_ spec: Spec) -> some View {
        let enabled = (model.settings ?? DaemonSettings())[keyPath: spec.enabled]
        return VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(RuleName.title(spec.id), isOn: model.binding(spec.enabled, custom: false))
                        .help("Turn the \(RuleName.title(spec.id)) rule on or off")
                    spec.rows().disabled(!enabled)
                } footer: {
                    Text(spec.footer)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { _open.wrappedValue = nil }.keyboardShortcut(.defaultAction)
                    .help("Close the rule's values")
            }
            .padding()
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The value rows of each per-app alert rule, the same in Settings and in an app's Alert Rules sheet.
@MainActor enum AlertRuleRows {
    typealias R = AlertRules

    @ViewBuilder static func sustainedCPU(_ r: Binding<R.SustainedCPU>, _ machine: Machine) -> some View {
        let cores = Double(machine.cores), cpuRange = R.SustainedCPU.percentRange(machine)
        // Stored of one core; shown as a share of all cores. Only a value other than the shown one is stored, so
        // showing never changes it.
        NumberRow(title: "Above", value: Binding(get: { share(r.wrappedValue.percent, cores) },
                                                 set: { if $0 != share(r.wrappedValue.percent, cores) { r.wrappedValue.percent = $0 * cores } }),
                  range: ((cpuRange.lowerBound / cores * 10).rounded(.up) / 10)...min(100, cpuRange.upperBound / cores),
                  step: 1, unit: "% of all cores", format: .number.precision(.fractionLength(0...1)))
        NumberRow(title: "For", value: r.minutes, range: R.SustainedCPU.minutesRange, unit: "min")
    }

    @ViewBuilder static func memoryGrowth(_ r: Binding<R.MemoryGrowth>, _ machine: Machine) -> some View {
        NumberRow(title: "Grows by", value: r.megabytes, range: R.MemoryGrowth.megabytesRange(machine), step: 50, unit: "MB")
        NumberRow(title: "Over", value: r.minutes, range: R.MemoryGrowth.minutesRange, step: 5, unit: "min")
    }

    static func memoryJump(_ r: Binding<R.MemoryJump>, _ machine: Machine) -> some View {
        NumberRow(title: "Grows by", value: r.megabytes, range: R.MemoryJump.megabytesRange(machine), step: 128, unit: "MB")
    }

    static func diskWrites(_ r: Binding<R.DiskWrites>) -> some View {
        NumberRow(title: "Above", value: units(r.bytesPerHour, 1_000_000_000), range: units(R.DiskWrites.bytesPerHourRange, 1_000_000_000),
                  unit: "GB per hour")
    }

    @ViewBuilder static func network(_ r: Binding<R.Network>) -> some View {
        NumberRow(title: "Above", value: units(r.bytesPerSecond, 1_000_000), range: units(R.Network.bytesPerSecondRange, 1_000_000),
                  unit: "MB/s")
        NumberRow(title: "For", value: r.minutes, range: R.Network.minutesRange, unit: "min")
    }

    @ViewBuilder static func energy(_ r: Binding<R.Energy>) -> some View {
        NumberRow(title: "Above", value: r.impact, range: R.Energy.impactRange, step: 50, unit: "impact")
        NumberRow(title: "For", value: r.minutes, range: R.Energy.minutesRange, unit: "min")
    }

    @ViewBuilder static func gpu(_ r: Binding<R.GPU>) -> some View {
        NumberRow(title: "Above", value: r.percent, range: R.GPU.percentRange, step: 5, unit: "%")
        NumberRow(title: "For", value: r.minutes, range: R.GPU.minutesRange, unit: "min")
    }

    /// CPU % of one core as % of all cores, to one decimal.
    private static func share(_ percent: Double, _ cores: Double) -> Double { (percent / cores * 10).rounded() / 10 }

    /// A byte value in whole `unit`s (GB or MB); a typed value too large for bytes is clamped, so validation rejects it.
    private static func units(_ bytes: Binding<Int64>, _ unit: Int64) -> Binding<Int> {
        let limit = Int64.max / unit
        return Binding(get: { Int(bytes.wrappedValue / unit) }, set: { bytes.wrappedValue = min(max(Int64($0), -limit), limit) * unit })
    }

    private static func units(_ range: ClosedRange<Int64>, _ unit: Int64) -> ClosedRange<Int> {
        Int(range.lowerBound / unit)...Int(range.upperBound / unit)
    }
}

private struct RecordingSettings: View {
    @Environment(SettingsModel.self) private var model
    /// A lower cap waits for confirmation: the next rollup deletes the history beyond it.
    private let _lowerCap = State<Int64?>(initialValue: nil)
    private let _addingTerminal = State(initialValue: false)

    var body: some View {
        let settings = model.settings ?? DaemonSettings()
        let cap = settings.sizeCapBytes
        Form {
            DaemonProblem()
            Group {
                Section {
                    Picker("Size cap", selection: Binding(get: { cap }, set: { new in
                        if new < cap { _lowerCap.wrappedValue = new } else { Task { await model.apply { $0.sizeCapBytes = new } } }
                    })) {
                        // A cap set outside these choices stays selectable, so the picker is never blank.
                        ForEach(DaemonSettings.sizeCapChoices.contains(cap) ? [] : [cap], id: \.self) { Text(gigabytes($0)).tag($0) }
                        ForEach(DaemonSettings.sizeCapChoices, id: \.self) { Text(gigabytes($0)).tag($0) }
                    }
                    .help("Set the largest size of the history database")
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
                        .contextMenu {
                            Button("Remove", systemImage: "minus.circle") {
                                Task { await model.apply { $0.terminalBundleIDs.removeAll { $0 == id } } }
                            }
                            .labelStyle(.titleAndIcon)
                            .help("Remove this app from the list")
                        }
                    }
                    Button("Add Terminal App…", systemImage: "plus") { _addingTerminal.wrappedValue = true }
                        .help("Choose an app to add to the Terminal pop-up")
                        .fileImporter(isPresented: _addingTerminal.projectedValue, allowedContentTypes: [.application]) { result in
                            if case .success(let url) = result { Task { await model.apply { try $0.addTerminal(appAt: url) } } }
                        }
                        .fileDialogDefaultDirectory(URL(filePath: "/Applications"))
                        .fileDialogConfirmationLabel("Add")
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
                    LabeledContent("Protocol version", value: String(ping.version))
                    LabeledContent("Uptime", value: Units.uptime(Double(ping.uptime)))
                    LabeledContent("Database") {
                        Text(ping.db).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    LabeledContent("PID", value: String(ping.pid))
                }
            }
            if !current {
                Section {
                    Text("curl -fsSL https://amx.henry.wang/install.sh | sh").font(.body.monospaced()).textSelection(.enabled)
                } header: {
                    Text("Install Command")
                } footer: {
                    Text("Run it in Terminal. It asks for an administrator password, installs the latest release and restarts the helper.")
                }
            }
            Section {
                Button("Check Helper Again") { Task { await model.load() } }
                    .help("Connect to the helper again and read its settings")
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
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.secondary)
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
            HStack(spacing: Layout.gap) {
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
