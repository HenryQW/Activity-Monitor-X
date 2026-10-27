import AMXCore
import AppKit
import SwiftUI

/// The menu bar item: an AppKit status item with a real menu, so every row gets the system highlight, keyboard
/// navigation, type-to-select and VoiceOver; a SwiftUI menu style cannot hold the gauges (D69). It asks `amxd` for live
/// data only while the menu is open (Review Focus 6), and `amxd` drops to its 5 s tick 3 s after the last request.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// Set by the label, which has the SwiftUI environment: Settings opens only through this action.
    var openSettings: OpenSettingsAction?
    private let client: DaemonClient
    private let alerts: AlertsModel
    private let history: HistoryModel
    private let selection: Selection
    private let unreadItem = NSMenuItem()
    private let appItems = (0..<5).map { _ in NSMenuItem() }
    private let appStatusItem = NSMenuItem()
    private let alertItems = (0..<3).map { _ in NSMenuItem() }
    private let noAlertsItem = NSMenuItem()
    private let allAlertsItem = NSMenuItem()
    private var top: [LiveTop.Row]?
    private var unreachable = false
    private var poll: Task<Void, Never>?

    init(client: DaemonClient, readout: MenuBarReadout, alerts: AlertsModel, history: HistoryModel, selection: Selection,
         preferences: Preferences) {
        (self.client, self.alerts, self.history, self.selection) = (client, alerts, history, selection)
        super.init()
        let gauges = NSMenuItem()
        let gaugesView = NSHostingView(rootView: MenuBarGauges().environment(readout).environment(alerts))
        gaugesView.frame.size = gaugesView.fittingSize
        gaugesView.autoresizingMask = .width
        gauges.view = gaugesView
        unreadItem.action = #selector(showUnread)
        appItems.forEach { $0.action = #selector(showApp) }
        alertItems.forEach { $0.action = #selector(showAlert) }
        allAlertsItem.action = #selector(showAlerts)
        allAlertsItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        allAlertsItem.toolTip = "Show all alerts in the Alerts screen"
        (appItems + alertItems + [unreadItem, allAlertsItem]).forEach { $0.target = self }
        // macOS 27 hides most menu images by default; the severity symbol carries meaning and every action has an icon
        // (user call, D69), so they always show.
        if #available(macOS 27, *) { (alertItems + [unreadItem, allAlertsItem]).forEach { $0.preferredImageVisibility = .visible } }
        // The column headings over the CPU and memory values (MW1).
        let appsHeader = NSMenuItem.sectionHeader(title: "Top Apps")
        appsHeader.attributedTitle = Self.columns("Top Apps", "CPU", "Memory", font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                                                  bold: true)
        let menu = NSMenu()
        menu.items = [gauges, unreadItem, .separator(), appsHeader] + appItems
            + [appStatusItem, .separator(), .sectionHeader(title: "Alerts")] + alertItems + [noAlertsItem, allAlertsItem, .separator(),
            action("Open Activity Monitor X", "macwindow", #selector(openMain), help: "Open the main window"),
            action("Settings…", "gear", #selector(showSettings), key: ",", help: "Open the Activity Monitor X settings"),
            action("Quit Activity Monitor X", "xmark.circle", #selector(quit), key: "q",
                   help: "Quit Activity Monitor X. The helper continues to record history.")]
        menu.delegate = self
        item.menu = menu

        let button = item.button!
        let label = LabelHostingView(rootView: MenuBarLabel(menu: self)
            .environment(readout).environment(alerts).environment(preferences).environment(selection))
        label.sizingOptions = []
        label.frame = button.bounds
        label.autoresizingMask = [.width, .height]
        button.addSubview(label)
        Task {
            for await shown in Observations({ preferences.menuBarShown }) { item.isVisible = shown }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        update()
        poll = Task {
            while !Task.isCancelled {
                do {
                    if let snapshot = try await client.live() { top = LiveTop.apps(snapshot, limit: 5) }
                    unreachable = false
                } catch {
                    unreachable = true
                }
                update()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) { poll?.cancel() }

    /// Sets the open menu's rows in place; the menu is never built again.
    private func update() {
        let unread = alerts.latestUnread
        unreadItem.isHidden = unread == nil
        if let unread {
            show(unread, in: unreadItem, title: unread.message, help: "\(unread.message). Show this alert in Apps.")
        }

        let rows = unreachable ? [] : top ?? []
        appStatusItem.title = unreachable ? "Helper not reachable" : "Loading…"
        appStatusItem.isHidden = !unreachable && top != nil
        for (i, item) in appItems.enumerated() {
            item.isHidden = i >= rows.count
            guard i < rows.count else { continue }
            let row = rows[i]
            if item.representedObject as? AppKey != row.app {
                // A copy: the cached icon is shared with the tables.
                let icon = AppIcon.image(for: row.app).copy() as! NSImage
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                item.representedObject = row.app
                item.toolTip = "Show \(row.app.name) in Apps"
            }
            item.attributedTitle = Self.title(row)
        }

        // The unread row already shows the newest unread alert. One line each, with its day (MW1); the rest are in Alerts.
        let recent = Array(alerts.alerts.filter { $0.id != unread?.id }.prefix(3))
        noAlertsItem.title = alerts.alerts.isEmpty ? "No alerts" : "No other alerts"
        noAlertsItem.isHidden = !recent.isEmpty
        for (i, item) in alertItems.enumerated() {
            item.isHidden = i >= recent.count
            guard i < recent.count else { continue }
            let event = recent[i]
            show(event, in: item, title: Self.fit(event.message, NSFont.menuFont(ofSize: 0), width: 280),
                 help: "\(event.message). Show this alert in Apps.")
            item.subtitle = AlertsView.time(event.ts)
        }
        allAlertsItem.isHidden = alerts.alerts.isEmpty
        allAlertsItem.attributedTitle = Self.columns("Show All Alerts", nil, alerts.alerts.count.formatted(), font: NSFont.menuFont(ofSize: 0))
    }

    private func show(_ event: EventMark, in item: NSMenuItem, title: String, help: String) {
        let critical = event.severity >= 2
        item.image = NSImage(systemSymbolName: critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                             accessibilityDescription: critical ? "Critical" : "Warning")?
            .withSymbolConfiguration(.init(paletteColors: [critical ? .systemRed : .systemYellow]))
        item.title = title
        item.toolTip = help
        item.representedObject = event
    }

    /// The app name, then CPU and memory right aligned in two columns. No text colour, so the highlight still reads.
    private static func title(_ row: LiveTop.Row) -> NSAttributedString {
        columns(fit(row.app.name, NSFont.menuFont(ofSize: 0), width: 160), Metric.cpu.format(row.cpu),
                Metric.memory.format(Double(row.mem)), font: NSFont.menuFont(ofSize: 0))
    }

    /// A name, then up to two values right aligned at the Top Apps columns, so a heading and the rows line up.
    private static func columns(_ name: String, _ first: String?, _ second: String, font: NSFont, bold: Bool = false) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 224), NSTextTab(textAlignment: .right, location: 304)]
        let weight: NSFont.Weight = bold ? .bold : .regular
        let title = NSMutableAttributedString(string: name, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: font.pointSize) : font,
                                                                          .paragraphStyle: style])
        title.append(NSAttributedString(string: "\t\(first ?? "")\t\(second)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: weight), .paragraphStyle: style]))
        return title
    }

    /// `text` cut with "…" to fit `width`.
    private static func fit(_ text: String, _ font: NSFont, width limit: CGFloat) -> String {
        let width = { (s: String) in (s as NSString).size(withAttributes: [.font: font]).width }
        guard width(text) > limit else { return text }
        var text = text
        while width(text + "…") > limit { text.removeLast() }
        return text + "…"
    }

    private func action(_ title: String, _ symbol: String, _ selector: Selector, key: String = "", help: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
        item.toolTip = help
        return item
    }

    @objc private func showApp(_ sender: NSMenuItem) {
        selection.query = ""
        selection.sidebar = .apps
        selection.app = (sender.representedObject as! AppKey)
        selection.openMain?()
    }

    @objc private func showUnread(_ sender: NSMenuItem) {
        alerts.markAllRead()
        showAlert(sender)
    }

    @objc private func showAlert(_ sender: NSMenuItem) {
        selection.openMain?()
        selection.reveal(sender.representedObject as! EventMark, history: history, rules: alerts.rules)
    }

    @objc private func showAlerts() {
        selection.sidebar = .alerts
        selection.openMain?()
    }

    @objc private func openMain() { selection.openMain?() }

    /// `openSettings` does not activate the app, so the window would open behind the frontmost app (Task 0).
    @objc private func showSettings() {
        NSApp.activate()
        openSettings?()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// The label draws over the status button; clicks go to the button, which opens the menu.
private final class LabelHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The menu's first row, a view with no highlight: CPU and Memory Pressure, each a gauge ring with its title and level (MW1).
private struct MenuBarGauges: View {
    @Environment(MenuBarReadout.self) private var readout
    @Environment(AlertsModel.self) private var alerts

    var body: some View {
        HStack(spacing: Layout.padding) {
            GaugeReadout(title: "CPU", percent: readout.percents?.cpu, level: cpuLevel)
            GaugeReadout(title: "Memory Pressure", percent: readout.percents?.pressure, level: pressureLevel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// The kernel level (1 normal, 2 warning, 4 critical) as 0, 1, 2.
    private var pressureLevel: Int? {
        readout.percents.map { $0.level >= 4 ? 2 : $0.level == 2 ? 1 : 0 }
    }

    /// The system CPU rule (SET-7); no level with the rule off.
    private var cpuLevel: Int? {
        let rule = alerts.rules.systemCPU
        guard rule.enabled, let cpu = readout.percents?.cpu else { return nil }
        return cpu >= rule.critical ? 2 : cpu >= rule.warning ? 1 : 0
    }
}

/// A capacity ring with the percent inside, tinted green, yellow or red by level as macOS shows memory pressure, with the
/// title and the level word beside it. CPU is already a share of all cores, so 0 to 100 fits both. "…" until the first
/// reading.
private struct GaugeReadout: View {
    let title: String
    let percent: Int?
    /// 0 normal, 1 warning, 2 critical; nil without a level.
    let level: Int?

    private var word: String? { level.map { ["Normal", "Warning", "Critical"][$0] } }

    var body: some View {
        HStack(spacing: Layout.inset) {
            Gauge(value: Double(percent ?? 0), in: 0...100) {
                Text(title)
            } currentValueLabel: {
                Text(percent.map { "\($0)" } ?? "…").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(level == 2 ? .red : level == 1 ? .yellow : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let word { Text(word).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([percent.map { "\($0) percent" } ?? "No reading yet", word].compactMap { $0 }.joined(separator: ", "))
    }
}
