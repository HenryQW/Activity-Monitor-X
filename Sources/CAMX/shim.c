// Derived from mac-performance-monitor (Zesty0wl), MIT License.
#include "CAMX.h"
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <string.h>
#include <libproc.h>
#include <sys/proc.h>
#include <sys/resource.h>
#include <sys/sysctl.h>

// Defined in <sys/proc.h> on macOS; guard in case a future SDK relocates it.
#ifndef P_TRANSLATED
#define P_TRANSLATED 0x00020000
#endif

int camx_is_translated(pid_t pid) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) {
        return -1;
    }
    return (info.kp_proc.p_flag & P_TRANSLATED) ? 1 : 0;
}

int camx_rusage(pid_t pid,
                uint64_t *phys_footprint,
                uint64_t *disk_read,
                uint64_t *disk_written,
                uint64_t *idle_wakeups) {
    struct rusage_info_v6 ru;
    memset(&ru, 0, sizeof(ru));
    if (proc_pid_rusage((int)pid, RUSAGE_INFO_V6, (rusage_info_t *)&ru) != 0) {
        return errno;
    }
    *phys_footprint = ru.ri_phys_footprint;
    *disk_read = ru.ri_diskio_bytesread;
    *disk_written = ru.ri_diskio_byteswritten;
    *idle_wakeups = ru.ri_pkg_idle_wkups + ru.ri_interrupt_wkups;
    return 0;
}

static pid_t (*responsible_fn)(pid_t);
static pthread_once_t responsible_once = PTHREAD_ONCE_INIT;

static void resolve_responsible(void) {
    responsible_fn = (pid_t (*)(pid_t))dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
}

pid_t camx_responsible_pid(pid_t pid) {
    pthread_once(&responsible_once, resolve_responsible);
    return responsible_fn ? responsible_fn(pid) : -1;
}
