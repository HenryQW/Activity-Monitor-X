import Foundation

/// Mach service `AMX.daemonLabel`, served by `amxd`.
@objc public protocol DaemonXPC {
    /// JSON `{"version":1,"uptime":<s>,"db":"<path>","pid":<n>}`.
    func ping(reply: @escaping (String) -> Void)
    /// Replies 0 on success, else an errno: `ESRCH` when no process runs at `pid` with `startTime`,
    /// `EPERM` when `SignalPolicy` refuses.
    func signal(pid: Int32, startTime: Double, signal: Int32, reply: @escaping (Int32) -> Void)
    /// JSON `LiveSnapshot` of the latest 1 s live sample, or nil before the first one. Each call keeps
    /// live sampling on for 3 s.
    func live(reply: @escaping (Data?) -> Void)
}
