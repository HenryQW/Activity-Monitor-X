import Darwin

public enum SignalPolicy {
    /// 0 if allowed, else `EPERM`. `pid <= 1` covers kernel_task (0), launchd (1) and process groups (negative).
    public static func check(pid: Int32, signal: Int32, selfPID: Int32) -> Int32 {
        guard pid > 1, pid != selfPID, signal == SIGTERM || signal == SIGKILL else { return EPERM }
        return 0
    }

    /// 0 if the process at `pid` started at `startTime`, else `ESRCH`, so a reused pid is never signalled.
    public static func checkIdentity(pid: Int32, startTime: Double) -> Int32 {
        ProcessReader.read(pid: pid)?.identity.startTime == startTime ? 0 : ESRCH
    }
}
