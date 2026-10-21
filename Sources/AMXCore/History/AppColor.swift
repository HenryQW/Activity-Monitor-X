public enum AppColor {
    /// 64-bit FNV-1a over the UTF-8 bytes of the app key, so an app keeps its colour across views and launches.
    public static func index(for app: AppKey, paletteSize: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in app.key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return Int(hash % UInt64(paletteSize))
    }

    /// Palette slots for the ranked top apps: in rank order each takes its own `index`, or the next free
    /// slot when a higher-ranked app has it, so no two top apps share a colour.
    public static func slots(for top: [AppKey], paletteSize: Int) -> [AppKey: Int] {
        precondition(top.count <= paletteSize, "more top apps than palette colours")
        var taken = Set<Int>()
        var result: [AppKey: Int] = [:]
        for app in top {
            var slot = index(for: app, paletteSize: paletteSize)
            while !taken.insert(slot).inserted { slot = (slot + 1) % paletteSize }
            result[app] = slot
        }
        return result
    }
}
