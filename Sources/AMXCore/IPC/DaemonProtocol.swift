import Foundation

/// Mach service `AMX.daemonLabel`, served by `amxd`.
@objc public protocol DaemonXPC {
    /// JSON `DaemonPing`: `{"db":"<path>","pid":<n>,"uptime":<s>,"version":3}`.
    func ping(reply: @escaping (String) -> Void)
    /// Replies 0 on success, else an errno: `ESRCH` when no process runs at `pid` with `startTime`,
    /// `EPERM` when `SignalPolicy` refuses, including a process of another user than the caller.
    func signal(pid: Int32, startTime: Double, signal: Int32, reply: @escaping (Int32) -> Void)
    /// JSON `LiveSnapshot` of the latest 1 s live sample, or nil before the first one. Each call keeps
    /// live sampling on for 3 s.
    func live(reply: @escaping (Data?) -> Void)
    /// The `settings.json` body that `amxd` applies now (the defaults when the file is missing or unreadable).
    func settings(reply: @escaping (Data) -> Void)
    /// Validates, saves and applies: rules and terminals from the next tick, the size cap at the next rollup. Replies nil on success, else the problem text;
    /// a refusal leaves the file and the applied settings as they were.
    func setSettings(_ json: Data, reply: @escaping (String?) -> Void)
}
