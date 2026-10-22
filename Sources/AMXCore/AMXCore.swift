import Foundation

public enum AMX {
    /// The release version. The MCP server reports it; `Packaging/Info.plist` has the same `CFBundleShortVersionString`.
    public static let version = "0.5.0"
    public static let bundleID = "com.henryqw.activitymonitorx"
    public static let cliID = "com.henryqw.activitymonitorx.amx"
    /// Dev builds (`make run-dev`): their own identity, so the Dock and Spotlight never open one instead of the app.
    public static let devBundleID = "com.henryqw.activitymonitorx.dev"
    public static let daemonLabel = "com.henryqw.activitymonitorx.daemon"
    public static let databasePath = "/Library/Application Support/ActivityMonitorX/history.sqlite"
    public static let settingsPath = "/Library/Application Support/ActivityMonitorX/settings.json"
    public static let tick: TimeInterval = 5
    /// Every commit rewrites the last page of each table it touches, so commits set amxd's disk writes.
    public static let ticksPerCommit = 3
    /// The WAL is synced at a checkpoint, so a power loss can lose up to this many ticks.
    public static let ticksPerCheckpoint = 60
}
