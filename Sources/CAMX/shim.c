// MIT License. See Packaging/Credits.html.
#include "CAMX.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
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
                uint64_t *idle_wakeups,
                uint64_t *cpu_time) {
    struct rusage_info_v6 ru;
    memset(&ru, 0, sizeof(ru));
    if (proc_pid_rusage((int)pid, RUSAGE_INFO_V6, (rusage_info_t *)&ru) != 0) {
        return errno;
    }
    *phys_footprint = ru.ri_phys_footprint;
    *disk_read = ru.ri_diskio_bytesread;
    *disk_written = ru.ri_diskio_byteswritten;
    *idle_wakeups = ru.ri_pkg_idle_wkups + ru.ri_interrupt_wkups;
    *cpu_time = ru.ri_user_time + ru.ri_system_time;
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

static int smart_capable(io_registry_entry_t entry) {
    CFTypeRef cap = IORegistryEntryCreateCFProperty(entry, CFSTR("NVMe SMART Capable"), kCFAllocatorDefault, 0);
    int yes = cap && CFGetTypeID(cap) == CFBooleanGetTypeID() && CFBooleanGetValue(cap);
    if (cap) CFRelease(cap);
    return yes;
}

int camx_nvme_smart_read(const char *bsd_name, uint8_t out[512]) {
    io_registry_entry_t entry = IOServiceGetMatchingService(
        kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsd_name));
    if (entry == IO_OBJECT_NULL) {
        return -1;
    }
    while (entry != IO_OBJECT_NULL && !smart_capable(entry)) {
        io_registry_entry_t parent = IO_OBJECT_NULL;
        kern_return_t kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        entry = kr == KERN_SUCCESS ? parent : IO_OBJECT_NULL;
    }
    if (entry == IO_OBJECT_NULL) {
        return -2;
    }

    // COM-style plug-in dance: create the plug-in for the service, then query
    // the SMART interface off it. Both must be released, in reverse order.
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        entry, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(entry);
    if (kr != KERN_SUCCESS || plugin == NULL) {
        return -3;
    }

    IONVMeSMARTInterface **smart = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
    if (hr != S_OK || smart == NULL) {
        IODestroyPlugInInterface(plugin);
        return -3;
    }

    NVMeSMARTData data;
    memset(&data, 0, sizeof(data));
    IOReturn ret = (*smart)->SMARTReadData(smart, &data);
    (*smart)->Release(smart);
    IODestroyPlugInInterface(plugin);
    if (ret != kIOReturnSuccess) {
        return -4;
    }

    // NVMeSMARTData is pragma pack(1) and exactly the 512-byte log page.
    _Static_assert(sizeof(NVMeSMARTData) == 512, "NVMe SMART log must be 512 bytes");
    memcpy(out, &data, sizeof(data));
    return 0;
}
