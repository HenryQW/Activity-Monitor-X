// Derived from mac-performance-monitor (Zesty0wl), MIT License.
#ifndef CAMX_H
#define CAMX_H

#include <sys/types.h>
#include <stdint.h>

/// 1 if the process runs translated under Rosetta 2, 0 if native, -1 on error.
int camx_is_translated(pid_t pid);

/// Reads per-process figures via proc_pid_rusage(RUSAGE_INFO_V6).
/// idle_wakeups = ri_pkg_idle_wkups + ri_interrupt_wkups. Out-params are
/// written only on success. Returns 0, or errno on failure.
int camx_rusage(pid_t pid,
                uint64_t *phys_footprint,
                uint64_t *disk_read,
                uint64_t *disk_written,
                uint64_t *idle_wakeups);

#endif
