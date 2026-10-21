import Foundation

/// The sidebar search: case- and diacritic-insensitive text in an app's name or path or a process's name, or a PID
/// exactly ("12" does not find 123).
public enum AppSearch {
    public static func matches(_ app: AppKey, _ query: String) -> Bool {
        app.name.localizedStandardContains(query) || app.key.localizedStandardContains(query)
    }

    public static func matches(_ process: ProcessRank, _ query: String) -> Bool {
        process.name.localizedStandardContains(query) || Int32(query) == process.pid
    }

    /// A matching app keeps all its processes; an app matched only through processes keeps just those.
    /// An empty query keeps everything.
    public static func filter(_ apps: [AppRank], query: String) -> [AppRank] {
        guard !query.isEmpty else { return apps }
        return apps.compactMap { app in
            if matches(app.app, query) { return app }
            let processes = app.processes.filter { matches($0, query) }
            return processes.isEmpty ? nil
                : AppRank(app: app.app, average: app.average, peak: app.peak, processes: processes)
        }
    }
}
