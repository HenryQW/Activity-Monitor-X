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

/// The pid responsible for `pid` (private libSystem call, resolved once
/// with dlsym). -1 when the symbol is missing, else the call's result.
pid_t camx_responsible_pid(pid_t pid);

/// Reads the 512-byte NVMe SMART / Health log of the disk with BSD name
/// `bsd_name`: finds its IOMedia, walks parents in the service plane to the
/// entry with "NVMe SMART Capable" = Yes, and reads the log through the
/// IONVMeSMARTUserClient plug-in. `out` is written only on success.
/// Returns 0, or -1 no such disk, -2 no SMART entry (external, USB),
/// -3 interface failed, -4 read failed.
int camx_nvme_smart_read(const char *bsd_name, uint8_t out[512]);

#endif
