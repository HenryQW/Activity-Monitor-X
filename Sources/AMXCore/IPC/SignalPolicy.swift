import Darwin

public enum SignalPolicy {
    /// 0 if allowed, else `EPERM`. `pid <= 1` covers kernel_task (0), launchd (1) and process groups (negative).
    public static func check(pid: Int32, signal: Int32, selfPID: Int32) -> Int32 {
        guard pid > 1, pid != selfPID, signal == SIGTERM || signal == SIGKILL else { return EPERM }
        return 0
    }

    /// 0 if the process at `pid` started at `startTime` and runs as `callerUID`. `ESRCH` when it did not start then,
    /// so a reused pid is never signalled; `EPERM` when it belongs to another user. The effective, real and saved
    /// uids must all match: a root process that only set its effective uid to the user's stays out of reach, as kill(2)
    /// would keep it.
    public static func checkIdentity(pid: Int32, startTime: Double, callerUID: uid_t) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard withUnsafeMutablePointer(to: &info, { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size) }) == size,
              Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6 == startTime else { return ESRCH }
        return info.pbi_uid == callerUID && info.pbi_ruid == callerUID && info.pbi_svuid == callerUID ? 0 : EPERM
    }
}
