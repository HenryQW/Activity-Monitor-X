import Darwin

public enum SignalPolicy {
    /// 0 if allowed, else `EPERM`. `pid <= 1` covers kernel_task (0), launchd (1) and process groups (negative).
    public static func check(pid: Int32, signal: Int32, selfPID: Int32) -> Int32 {
        guard pid > 1, pid != selfPID, signal == SIGTERM || signal == SIGKILL else { return EPERM }
        return 0
    }
}
