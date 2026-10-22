import AMXCore

extension RuleName {
    /// A rule's name as Settings, the Alert Rules sheet and the inspector show it; an unknown rule shows as it is stored.
    static func title(_ rule: String) -> String {
        switch rule {
        case sustainedCPU: "Sustained CPU"
        case memoryGrowth: "Memory Growth"
        case memoryJump: "Memory Jump"
        case pressure: "Memory Pressure"
        case thermal: "Thermal State"
        case diskWrites: "Disk Writes"
        case network: "Network"
        case energy: "Energy Impact"
        case gpu: "GPU"
        case swap: "Swap Used"
        case freeSpace: "Free Disk Space"
        default: rule
        }
    }
}
