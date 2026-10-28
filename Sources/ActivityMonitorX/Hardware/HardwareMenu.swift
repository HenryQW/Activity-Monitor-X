import AMXCore
import AppKit
import IOBluetooth
import SwiftUI

/// The Hardware inventory row's menu: actions on the thing the row is (a Bluetooth device, a volume), its System
/// Settings pane, then Copy and Show in Inspector on every row.
struct HardwareMenu: View {
    let row: HardwareRow
    let hardware: HardwareModel
    let selection: Selection
    let diskMap: DiskMapModel
    /// The device that Forget asks about first.
    @Binding var forgetting: HardwareRow?

    var body: some View {
        Group {
            if let address = row.address {
                // Paired devices that are not connected are under a "Not Connected" group.
                if row.id.contains("/Not Connected/") {
                    Button("Connect", systemImage: "link") { hardware.bluetooth(.connect, address: address, name: row.name) }
                        .help("Connect \(row.name) to this Mac")
                } else {
                    Button("Disconnect", systemImage: "link.badge.minus") { hardware.bluetooth(.disconnect, address: address, name: row.name) }
                        .help("Disconnect \(row.name). It stays paired.")
                }
                Button("Forget…", systemImage: "minus.circle") { forgetting = row }
                    .help("Remove the pairing of \(row.name). To use it again, pair it again.")
                Divider()
            }
            if let volume {
                ShowInFinderButton(path: volume.mountPoint, help: "Show \(volume.name) in the Finder")
                Button("Show in Space", systemImage: "chart.pie") {
                    diskMap.open(.volume(volume))
                    selection.sidebar = .disk
                    selection.diskPane = .space
                }
                .help("Show what uses the space on \(volume.name)")
                if !volume.isInternal {
                    // The unmount notification reads the inventory again.
                    Button("Eject", systemImage: "eject") { Task { hardware.actionFailure = await volume.eject() } }
                        .help("Eject \(volume.name) so that you can disconnect it safely")
                }
                Divider()
            }
            if let pane = Self.pane(of: row) {
                Button("Open \(pane.name) Settings", systemImage: "gear") { NSWorkspace.shared.open(pane.url) }
                    .help("Open \(pane.name) in System Settings")
                Divider()
            }
            // A parent's value is its count, not data.
            Button("Copy", systemImage: "doc.on.doc") { DiskItemMenu.copy(row.value.isEmpty || row.children != nil ? row.name : "\(row.name): \(row.value)") }
                .help("Copy the name and the value")
            Button("Show in Inspector", systemImage: "sidebar.trailing") {
                hardware.selected = row.id
                selection.inspectorShown = true
            }
            .help("Show \(row.name) in the inspector")
        }
        .labelStyle(.titleAndIcon)
    }

    /// The startup volume or an external drive's volume the row is, by its mount point.
    private var volume: VolumeInfo? {
        let mount = row.children?.first { $0.id.hasSuffix("=mount_point") }?.value
        return mount.flatMap { m in hardware.volumes.first { $0.mountPoint == m } }
    }

    /// The System Settings pane for a row in a section that has one.
    static func pane(of row: HardwareRow) -> (name: String, url: URL)? {
        let panes = [("Bluetooth/", "Bluetooth", "com.apple.BluetoothSettings"),
                     ("Graphics and Displays/", "Displays", "com.apple.Displays-Settings.extension"),
                     ("Network/", "Network", "com.apple.Network-Settings.extension"),
                     ("Audio/", "Sound", "com.apple.Sound-Settings.extension")]
        guard let pane = panes.first(where: { row.id.hasPrefix($0.0) || row.id + "/" == $0.0 }) else { return nil }
        return (pane.1, URL(string: "x-apple.systempreferences:\(pane.2)")!)
    }
}

enum BluetoothAction: String { case connect = "Connect", disconnect = "Disconnect", forget = "Forget" }

extension HardwareModel {
    /// Connect and Disconnect are IOBluetooth's; no public call removes a pairing, so Forget calls the private `remove`
    /// (user call, D78). Off the main actor, as a connection can take seconds; then the inventory is read again.
    func bluetooth(_ action: BluetoothAction, address: String, name: String) {
        Task {
            let failed = await Task.detached { () -> Bool in
                guard let device = IOBluetoothDevice(addressString: address) else { return true }
                // The menu's state is the last capture's: a device that is already as asked is a success.
                switch action {
                case .connect: return device.openConnection() != kIOReturnSuccess && !device.isConnected()
                case .disconnect: return device.closeConnection() != kIOReturnSuccess && device.isConnected()
                case .forget:
                    guard device.responds(to: Selector(("remove"))) else { return true }
                    device.perform(Selector(("remove")))
                    return false
                }
            }.value
            await refresh()
            // `remove` reports nothing: a device still in the inventory was not forgotten.
            if failed || action == .forget && Self.holds(address, rows) {
                actionFailure = ("Cannot \(action.rawValue) \(name)", "macOS did not accept the request. Try it in Bluetooth settings.")
            }
        }
    }
    private static func holds(_ address: String, _ rows: [HardwareRow]) -> Bool {
        rows.contains { $0.address == address || holds(address, $0.children ?? []) }
    }
}
