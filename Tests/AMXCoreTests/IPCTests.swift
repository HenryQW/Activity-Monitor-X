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

    @Test func identityMismatchIsESRCH() throws {
        let me = try #require(ProcessReader.read(pid: getpid())).identity
        #expect(SignalPolicy.checkIdentity(pid: me.pid, startTime: me.startTime, callerUID: geteuid()) == 0)
        #expect(SignalPolicy.checkIdentity(pid: me.pid, startTime: me.startTime - 1, callerUID: geteuid()) == ESRCH)
    }

    @Test func otherUserIsEPERM() throws {
        let me = try #require(ProcessReader.read(pid: getpid())).identity
        #expect(SignalPolicy.checkIdentity(pid: me.pid, startTime: me.startTime, callerUID: geteuid() + 1) == EPERM)
    }

    @Test func pingJSONShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(DaemonPing(version: 2, uptime: 5, db: "/x", pid: 9))
        #expect(String(decoding: json, as: UTF8.self) == #"{"db":"/x","pid":9,"uptime":5,"version":2}"#)
    }

    @Test func requirementStringExact() {
        #expect(SigningRequirement.string(leafSHA1Hex: "abc123") ==
            #"(identifier "com.henryqw.activitymonitorx" or identifier "com.henryqw.activitymonitorx.amx") and certificate leaf = H"abc123""#)
    }
}
