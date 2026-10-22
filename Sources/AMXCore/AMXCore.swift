import Foundation

public enum AMX {
    public static let bundleID = "com.henryqw.activitymonitorx"
    public static let cliID = "com.henryqw.activitymonitorx.amx"
    public static let daemonLabel = "com.henryqw.activitymonitorx.daemon"
    public static let databasePath = "/Library/Application Support/ActivityMonitorX/history.sqlite"
    public static let settingsPath = "/Library/Application Support/ActivityMonitorX/settings.json"
    public static let tick: TimeInterval = 5
    /// Every commit rewrites the last page of each table it touches, so commits set amxd's disk writes.
    public static let ticksPerCommit = 3
    /// The WAL is synced at a checkpoint, so a power loss can lose up to this many ticks.
    public static let ticksPerCheckpoint = 60
}
