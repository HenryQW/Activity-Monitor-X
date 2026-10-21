@testable import AMXCore
import CAMX
import Foundation
import Testing

@Suite struct ShimTests {
    @Test func shimReadsOwnFootprint() {
        var footprint: UInt64 = 0, read: UInt64 = 0, written: UInt64 = 0, wakeups: UInt64 = 0
        #expect(camx_rusage(getpid(), &footprint, &read, &written, &wakeups) == 0)
        #expect(footprint > 0)
        // pid 1 is root-owned; non-root callers are refused.
        if getuid() != 0 {
            #expect(camx_rusage(1, &footprint, &read, &written, &wakeups) == EPERM)
        }
    }

    @Test func translatedFlagForSelf() {
        #expect(camx_is_translated(getpid()) == 0)
    }
}
