import AMXCore
import os
import SwiftUI
import UserNotifications

@main
struct ActivityMonitorXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let history: HistoryModel
    private let live: LiveModel
    private let selection = Selection()
    private let groups: GroupsModel
    private let alerts: AlertsModel
    private let disk: DiskModel
    /// App level: the last Disk Map tree stays while the app runs (M5-D10).
    private let diskMap: DiskMapModel
    private let hardware: HardwareModel
    /// App-wide, so the inspector reads what the Energy screen reads.
    private let energy = EnergyModel()
    private let calendar: CalendarModel
    private let readout = MenuBarReadout()
    private let settings: SettingsModel
    /// Kept here: the notification center holds its delegate weakly. Nil outside the bundle (`swift run`).
    private let notifier: Notifier?

    init() {
        // Hover hints show after 1 s of rest: this app's defaults only, never a system setting.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 1000])
        let history = HistoryModel()
        self.history = history
        live = LiveModel(history: history, selection: selection)
        groups = GroupsModel(history: history)
        calendar = CalendarModel(history: history)
        let alerts = AlertsModel(client: live.client, history: history)
        self.alerts = alerts
        settings = SettingsModel(client: live.client, alerts: alerts)
        let volumeSource = VolumeSource()
        disk = DiskModel(volumeSource: volumeSource)
        diskMap = DiskMapModel(volumeSource: volumeSource)
        hardware = HardwareModel(volumeSource: volumeSource)
        if Bundle.main.bundleIdentifier == AMX.bundleID {
            let notifier = Notifier(selection: selection, history: history, alerts: alerts)
            UNUserNotificationCenter.current().delegate = notifier
            alerts.onNew = { notifier.post($0) }
            Task { await notifier.authorize() }
            self.notifier = notifier
        } else {
            notifier = nil
            Logger(subsystem: AMX.bundleID, category: "notifications").notice("notifications off: not running from the app bundle")
        }
        // App level, not the window's .task: the badge and notifications keep up with the window closed.
        Task { await alerts.run() }
        // Runs while the menu bar item is hidden too; two cheap reads every 5 s.
        Task { [readout] in await readout.run() }
        appDelegate.statusMenu = StatusMenu(client: live.client, readout: readout, alerts: alerts, history: history,
                                            selection: selection, preferences: appDelegate.preferences)
    }

    /// The 228 KB glossary decodes off the main actor; nil without a bundle (`swift run`).
    private static func loadGlossary() async -> Glossary? {
        guard let url = Bundle.main.url(forResource: "glossary", withExtension: "json") else { return nil }
        return await Task.detached {
            do { return try JSONDecoder().decode(Glossary.self, from: Data(contentsOf: url)) } catch {
                Logger(subsystem: AMX.bundleID, category: "glossary").error("glossary: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    var body: some Scene {
        Window("Activity Monitor X", id: "main") {
            MainWindow()
                // Dates and day boundaries read the forced zone as they draw: a new zone draws the window again.
                .id(appDelegate.preferences.zoneKey)
                .environment(\.timeZone, AppTime.zone)
                .environment(\.calendar, AppTime.calendar)
                .environment(history)
                .environment(live)
                .environment(selection)
                .environment(groups)
                .environment(alerts)
                .environment(disk)
                .environment(diskMap)
                .environment(hardware)
                .environment(energy)
                .environment(calendar)
                .environment(readout)
                .environment(settings)
                .environment(appDelegate.preferences)
                .task { await history.run() }
                .task { if history.glossary == nil { history.glossary = await Self.loadGlossary() } }
                .task { await groups.run() }
        }
        .defaultSize(width: 1200, height: 760)
        .defaultLaunchBehavior(.presented)
        .commands {
            SidebarCommands()
            CommandGroup(after: .pasteboard) {
                Group {
                    Divider()
                    Button("Find…", systemImage: "magnifyingglass") { selection.searchPresented = true }
                        .keyboardShortcut("f")
                }
                    .labelStyle(.titleAndIcon)
            }
            GroupCommands(selection: selection, groups: groups)
            GoCommands(selection: selection, history: history, diskMap: diskMap, alerts: alerts, calendar: calendar)
            DataCommands(history: history, selection: selection)
            ProcessCommands(selection: selection)
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(appDelegate.preferences)
                .environment(notifier)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    /// Kept here: menu items hold their target weakly.
    var statusMenu: StatusMenu?

    func applicationWillFinishLaunching(_ notification: Notification) { preferences.applyAppearance() }

    /// A menu bar item alone does not keep a SwiftUI app running (Task 0 probe 1): while it is shown, closing the
    /// window keeps the app, so the alert poll and notifications go on; while hidden, the app quits (probe 3).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !preferences.menuBarShown }
}
