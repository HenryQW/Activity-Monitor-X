import Foundation
import IOKit
import IOKit.ps

/// The Mac's power right now, in watts. A value the Mac does not report is nil, never 0.
public struct PowerReading: Equatable, Sendable {
    public struct Battery: Equatable, Sendable {
        /// Charge 0–100.
        public var percent: Int?
        public var charging: Bool
        /// Watts into the battery (positive, charging) or out of it (negative).
        public var watts: Double?
    }

    public var adapterConnected: Bool
    /// Watts in from the adapter; 0 while none is connected.
    public var adapterWatts: Double?
    /// The adapter's rated watts.
    public var adapterRating: Double?
    /// Nil on a Mac without a battery.
    public var battery: Battery?

    /// Watts the Mac uses: adapter in plus battery out, less battery in.
    public var systemWatts: Double? {
        guard let adapter = adapterWatts else { return nil }
        guard let battery else { return adapter }
        guard let watts = battery.watts else { return nil }
        return max(0, adapter - max(0, watts)) - min(0, watts)
    }

    public init(adapterConnected: Bool, adapterWatts: Double?, adapterRating: Double? = nil, battery: Battery?) {
        (self.adapterConnected, self.adapterWatts, self.adapterRating, self.battery) = (adapterConnected, adapterWatts, adapterRating, battery)
    }

    /// From the providing power source type ("AC Power"), the internal battery's power source description and the
    /// `AppleSmartBattery` registry properties. Registry milliamps are signed 64-bit values in unsigned form.
    public init(providing: String?, source: [String: Any]?, battery registry: [String: Any]?) {
        func number(_ dict: [String: Any]?, _ key: String) -> Int64? { (dict?[key] as? NSNumber)?.int64Value }
        adapterConnected = providing.map { $0 == "AC Power" } ?? (registry?["ExternalConnected"] as? Bool ?? false)
        let telemetry = registry?["PowerTelemetryData"] as? [String: Any]
        adapterWatts = adapterConnected ? number(telemetry, "SystemPowerIn").map { Double($0) / 1000 } : 0
        adapterRating = number(registry?["AdapterDetails"] as? [String: Any], "Watts").map(Double.init)
        let installed = source?["Type"] as? String == "InternalBattery" || registry?["BatteryInstalled"] as? Bool == true
        guard installed else { battery = nil; return }
        let percent = number(source, "Current Capacity").flatMap { current in
            number(source, "Max Capacity").flatMap { $0 > 0 ? Int(current * 100 / $0) : nil }
        } ?? number(registry, "CurrentCapacity").map { Int($0) }
        let milliamps = number(registry, "InstantAmperage") ?? number(registry, "Amperage")
        let watts = number(registry, "Voltage").flatMap { mV in milliamps.map { Double(mV) * Double($0) / 1_000_000 } }
        battery = Battery(percent: percent, charging: source?["Is Charging"] as? Bool ?? registry?["IsCharging"] as? Bool ?? false,
                          watts: watts)
    }
}

/// Reads `PowerReading` from the power source APIs and the battery registry entry; no privilege needed.
public enum PowerReader {
    private static let keys = ["ExternalConnected", "BatteryInstalled", "IsCharging", "CurrentCapacity", "Voltage",
                               "InstantAmperage", "Amperage", "AdapterDetails", "PowerTelemetryData"]

    public static func read() -> PowerReading {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let providing = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        let list = info.flatMap { IOPSCopyPowerSourcesList($0)?.takeRetainedValue() } as? [CFTypeRef] ?? []
        let source = list.lazy.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0["Type"] as? String == "InternalBattery" }
        return PowerReading(providing: providing, source: source, battery: registry())
    }

    private static func registry() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var out: [String: Any] = [:]
        for key in keys {
            out[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        return out
    }
}
