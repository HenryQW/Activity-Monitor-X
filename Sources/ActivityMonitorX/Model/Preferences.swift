import AMXCore
import AppKit
import Observation
import os
import ServiceManagement

enum MenuBarStyle: String {
    case text, chart
}

/// The screen the main window opens at: Last Screen, or one of the fixed ones.
enum StartScreen: String, CaseIterable {
    case last, apps, calendar, alerts, energy, disk, hardware

    /// Disk Map was a screen before it became Disk's Space pill; stored, it reads as Disk (`Selection.diskPane`).
    static let diskMap = "diskMap"

    init?(stored: String?) { self.init(rawValue: stored == Self.diskMap ? "disk" : stored ?? "") }

    var label: String {
        switch self {
        case .last: "Last Screen"
        case .apps: "Apps"
        case .calendar: "Calendar"
        case .alerts: "Alerts"
        case .energy: "Energy"
        case .disk: "Disk"
        case .hardware: "Hardware"
        }
    }

    var item: SidebarItem {
        switch self {
        case .last, .apps: .apps
        case .calendar: .calendar
        case .alerts: .alerts
        case .energy: .energy
        case .disk: .disk
        case .hardware: .hardware
        }
    }

    /// Nil for a pinned app or a group: the last screen stays as it was.
    init?(_ item: SidebarItem) {
        guard let screen = Self.allCases.first(where: { $0 != .last && $0.item == item }) else { return nil }
        self = screen
    }
}

/// The time range the main window opens at: Last Used, or one of the quick ranges.
enum StartRange: String, CaseIterable {
    case last, live, hour, day, week, month, quarter

    var label: String { self == .last ? "Last Used" : range.label }

    var range: HistoryRange {
        switch self {
        case .live: .live
        case .hour: .hour
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .last, .day: .day
        }
    }

    init(_ range: HistoryRange) {
        self = Self.allCases.first { $0 != .last && $0.range == range } ?? .day
    }
}

/// App choices kept in the app: the menu bar item (M4-D11), appearance and launch at login.
@Observable @MainActor
final class Preferences {
    enum Appearance: String, CaseIterable { case system, light, dark }

    private static let menuBarKey = "menuBarShown", appearanceKey = "appearance", styleKey = "menuBarStyle"
    private static let zoneKey = "timeZone", extraZonesKey = "extraZones", firstWeekdayKey = "firstWeekday"
    private static let openAtKey = "openAt", openRangeKey = "openRange", lastScreenKey = "lastScreen", lastRangeKey = "lastRange"
    private static let log = Logger(subsystem: AMX.bundleID, category: "preferences")
    /// Nil outside the app bundle (`swift run`): a login item needs the bundle.
    private static let service = Bundle.main.bundleIdentifier == AMX.bundleID ? SMAppService.mainApp : nil

    /// Shown by default; while shown, closing the window keeps the app running for notifications.
    var menuBarShown = UserDefaults.standard.object(forKey: Preferences.menuBarKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuBarShown, forKey: Self.menuBarKey) }
    }

    /// System follows the macOS light or dark setting as it changes; Light and Dark hold for this app only.
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: Preferences.appearanceKey) ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            applyAppearance()
        }
    }

    /// A time zone forced on every screen's dates and day boundaries, by identifier; nil follows system time.
    var timeZoneID = UserDefaults.standard.string(forKey: Preferences.zoneKey) {
        didSet {
            UserDefaults.standard.set(timeZoneID, forKey: Self.zoneKey)
            AppTime.apply(zoneID: timeZoneID, firstWeekday: firstWeekday)
        }
    }
    /// Counts system zone changes, so a view keyed by `zoneKey` draws again under Follow System.
    private var systemZoneChanges = 0
    var zoneKey: String { "\(timeZoneID ?? "")/\(systemZoneChanges)" }
    /// The zones whose hours the Calendar's Week and Day label next to the shown zone's.
    var extraZoneIDs = UserDefaults.standard.stringArray(forKey: Preferences.extraZonesKey) ?? [] {
        didSet { UserDefaults.standard.set(extraZoneIDs, forKey: Self.extraZonesKey) }
    }
    /// The day weeks start on, 1 (Sunday) to 7; nil follows the system setting.
    var firstWeekday = UserDefaults.standard.object(forKey: Preferences.firstWeekdayKey) as? Int {
        didSet {
            UserDefaults.standard.set(firstWeekday, forKey: Self.firstWeekdayKey)
            AppTime.apply(zoneID: timeZoneID, firstWeekday: firstWeekday)
        }
    }

    /// An unknown stored value reads as the default.
    var openAt = StartScreen(stored: UserDefaults.standard.string(forKey: Preferences.openAtKey)) ?? .last {
        didSet { UserDefaults.standard.set(openAt.rawValue, forKey: Self.openAtKey) }
    }
    var openRange = StartRange(rawValue: UserDefaults.standard.string(forKey: Preferences.openRangeKey) ?? "") ?? .last {
        didSet { UserDefaults.standard.set(openRange.rawValue, forKey: Self.openRangeKey) }
    }
    /// The screen and quick range of the last session: what Last Screen and Last Used open at.
    var lastScreen = StartScreen(stored: UserDefaults.standard.string(forKey: Preferences.lastScreenKey)) ?? .apps {
        didSet { UserDefaults.standard.set(lastScreen.rawValue, forKey: Self.lastScreenKey) }
    }
    /// A stored screen is Disk Map: Disk opens with Space until a pill is chosen.
    static var storedDiskMap: Bool {
        [openAtKey, lastScreenKey].contains { UserDefaults.standard.string(forKey: $0) == StartScreen.diskMap }
    }
    var lastRange = StartRange(rawValue: UserDefaults.standard.string(forKey: Preferences.lastRangeKey) ?? "") ?? .day {
        didSet { UserDefaults.standard.set(lastRange.rawValue, forKey: Self.lastRangeKey) }
    }
    var startScreen: SidebarItem { (openAt == .last ? lastScreen : openAt).item }
    var startRange: HistoryRange { (openRange == .last ? lastRange : openRange).range }
    /// Set once the main window has opened at its start screen: reopening the window keeps what it shows.
    var startApplied = false

    func applyAppearance() {
        NSApp.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var menuBarStyle = UserDefaults.standard.string(forKey: Preferences.styleKey).flatMap(MenuBarStyle.init) ?? .chart {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Self.styleKey) }
    }

    /// On while registered, also while Login Items waits for approval. Setting it registers or unregisters.
    var launchAtLogin: Bool {
        get { loginOn }
        set {
            guard let service = Self.service else { return }
            do {
                try newValue ? service.register() : service.unregister()
                loginError = nil
            } catch {
                loginError = error.localizedDescription
                Self.log.error("login item: \(error.localizedDescription, privacy: .public)")
            }
            refreshLogin()
        }
    }
    private(set) var loginError: String?
    /// Registered, but Login Items waits for the owner to allow it.
    private(set) var loginNeedsApproval = false
    private var loginOn = false

    init() {
        if Self.service == nil { Self.log.notice("launch at login off: not running from the app bundle") }
        AppTime.apply(zoneID: timeZoneID, firstWeekday: firstWeekday)
        AppTime.followSystemChanges { [weak self] in self?.systemZoneChanges += 1 }
        refreshLogin()
    }

    /// The owner can change it in System Settings; Settings re-reads it when its window gains focus.
    func refreshLogin() {
        guard let service = Self.service else { return }
        // A never-registered app reads `notFound`, not `notRegistered` (Task 0 probe 6).
        loginOn = [.enabled, .requiresApproval].contains(service.status)
        loginNeedsApproval = service.status == .requiresApproval
    }
}
