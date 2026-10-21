// Derived from mac-performance-monitor (Zesty0wl), MIT License.
import CAMX
import Darwin
import Foundation

enum ProcessReader {
    private static let timebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (info.numer, max(info.denom, 1))
    }()

    static func listPIDs() -> [Int32] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }
        let capacity = Int(needed) + 512
        var pids = [pid_t](repeating: 0, count: capacity)
        let ret = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard ret > 0 else { return [] }
        return pids[0..<min(Int(ret), capacity)].filter { $0 > 0 }
    }

    /// nil when the process is gone or unreadable.
    static func read(pid: Int32) -> RawProcess? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let ret = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, size) }
        guard ret == size else { return nil }

        var footprint: UInt64 = 0, diskRead: UInt64 = 0, diskWritten: UInt64 = 0, wakeups: UInt64 = 0
        guard camx_rusage(pid, &footprint, &diskRead, &diskWritten, &wakeups) == 0 else { return nil }

        let name = cString(info.pbsd.pbi_name).nonEmpty ?? cString(info.pbsd.pbi_comm)
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let cpu = info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system

        return RawProcess(
            identity: ProcessIdentity(
                pid: pid,
                startTime: Double(info.pbsd.pbi_start_tvsec) + Double(info.pbsd.pbi_start_tvusec) / 1e6),
            name: name,
            path: pathLen > 0
                ? String(decoding: pathBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil,
            uid: info.pbsd.pbi_uid,
            cpuNanos: CPUMath.machToNanos(cpu, numer: timebase.numer, denom: timebase.denom),
            footprint: footprint,
            diskRead: diskRead,
            diskWritten: diskWritten,
            wakeups: wakeups,
            translated: camx_is_translated(pid) == 1)
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
