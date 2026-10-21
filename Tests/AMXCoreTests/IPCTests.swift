@testable import AMXCore
import Foundation
import Testing

@Suite struct IPCTests {
    @Test func refusesProtectedPIDs() {
        let me = getpid()
        for pid: Int32 in [0, 1, me] {
            #expect(SignalPolicy.check(pid: pid, signal: SIGTERM, selfPID: me) == EPERM)
        }
    }

    @Test func refusesOtherSignals() {
        #expect(SignalPolicy.check(pid: 4242, signal: SIGHUP, selfPID: getpid()) == EPERM)
    }

    @Test func allowsTermAndKill() {
        #expect(SignalPolicy.check(pid: 4242, signal: SIGTERM, selfPID: getpid()) == 0)
        #expect(SignalPolicy.check(pid: 4242, signal: SIGKILL, selfPID: getpid()) == 0)
    }

    @Test func requirementStringExact() {
        #expect(SigningRequirement.string(leafSHA1Hex: "abc123") ==
            #"(identifier "com.henryqw.activitymonitorx" or identifier "com.henryqw.activitymonitorx.amx") and certificate leaf = H"abc123""#)
    }
}
