public enum AppColor {
    /// 64-bit FNV-1a over the UTF-8 bytes of the app key, so an app keeps its colour across views and launches.
    public static func index(for app: AppKey, paletteSize: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in app.key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return Int(hash % UInt64(paletteSize))
    }

    /// Palette slots for the top apps, all distinct. An app keeps the slot it got the first time it was coloured
    /// (`stored`, by app key), in every view and metric. Apps go in key order, not rank order, so the same set of apps
    /// always gets the same colours: of two apps sharing a stored slot the smaller key keeps it and the other gets the
    /// next free slot for this call only. A new app takes its `index`, or the next free slot, and that slot is stored.
    public static func slots(for top: [AppKey], paletteSize: Int, stored: inout StoredSlots) -> [AppKey: Int] {
        precondition(top.count <= paletteSize, "more top apps than palette colours")
        let apps = top.sorted { ($0.key, $0.name) < ($1.key, $1.name) }
        var taken = Set<Int>()
        var result: [AppKey: Int] = [:]
        // Stored slots first, so a new app never takes the slot of a shown app.
        for app in apps {
            if let slot = stored[app.key].map({ $0 % paletteSize }), taken.insert(slot).inserted { result[app] = slot }
        }
        for app in apps where result[app] == nil {
            var slot = (stored[app.key] ?? index(for: app, paletteSize: paletteSize)) % paletteSize
            while !taken.insert(slot).inserted { slot = (slot + 1) % paletteSize }
            result[app] = slot
            if stored[app.key] == nil { stored.add(app.key, slot) }
        }
        return result
    }
}

/// Each app's palette slot by app key, in the order the apps were first coloured; the newest `limit` apps are kept.
public struct StoredSlots: Codable, Sendable, Equatable {
    public static let limit = 256
    /// Oldest first.
    public private(set) var keys: [String] = []
    private var slots: [String: Int] = [:]

    public init() {}

    public subscript(key: String) -> Int? { slots[key] }

    public mutating func add(_ key: String, _ slot: Int) {
        keys.append(key)
        slots[key] = slot
        if keys.count > Self.limit { slots[keys.removeFirst()] = nil }
    }
}
