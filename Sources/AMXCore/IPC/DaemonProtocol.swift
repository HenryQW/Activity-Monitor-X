import Foundation

/// Mach service `AMX.daemonLabel`, served by `amxd`.
@objc public protocol DaemonXPC {
    /// JSON `{"version":1,"uptime":<s>,"db":"<path>","pid":<n>}`.
    func ping(reply: @escaping (String) -> Void)
    /// Replies 0 on success, else an errno (`EPERM` when `SignalPolicy` refuses).
    func signal(pid: Int32, signal: Int32, reply: @escaping (Int32) -> Void)
}
