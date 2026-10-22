// MIT License. See Packaging/Credits.html.
import Foundation
import IOKit

/// GPU figures from the `IOAccelerator` registry entries; no privilege needed.
public enum GPUReader {
    /// Device utilisation 0–100 of the busiest accelerator.
    public static func deviceUtilization() -> Double {
        var best = 0.0
        forEachAccelerator { accelerator in
            guard let stats = property(accelerator, "PerformanceStatistics") as? [String: Any],
                  let util = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? Int else { return }
            best = max(best, Double(util))
        }
        return best
    }

    /// Accumulated GPU nanoseconds per pid, summed over its Metal contexts.
    ///
    /// Each context is an `IOUserClient` child of the accelerator (not a registered
    /// service, so matching cannot find it) with `IOUserClientCreator` "pid 413, Name"
    /// and `AppUsage` entries carrying `accumulatedGPUTime` in nanoseconds.
    public static func processNanos() -> [Int32: UInt64] {
        var out: [Int32: UInt64] = [:]
        forEachAccelerator { accelerator in
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS
            else { return }
            defer { IOObjectRelease(children) }
            var child = IOIteratorNext(children)
            while child != 0 {
                if IOObjectConformsTo(child, "IOUserClient") != 0,
                   let creator = property(child, "IOUserClientCreator") as? String,
                   let pid = pid(fromCreator: creator) {
                    let usage = property(child, "AppUsage") as? [[String: Any]] ?? []
                    for entry in usage {
                        guard let n = entry["accumulatedGPUTime"] as? NSNumber, n.int64Value >= 0 else { continue }
                        out[pid, default: 0] &+= n.uint64Value
                    }
                }
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
        }
        return out
    }

    static func pid(fromCreator creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        return Int32(creator.dropFirst(4).prefix { $0.isNumber })
    }

    private static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
