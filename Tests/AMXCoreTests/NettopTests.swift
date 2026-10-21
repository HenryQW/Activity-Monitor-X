@testable import AMXCore
import Foundation
import os
import Testing

@Suite struct NettopTests {
    private static let header = "time,,bytes_in,bytes_out,"

    private func id(_ pid: Int32 = 77, start: Double) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startTime: start)
    }

    /// Feeds blocks 5 s apart; the last header completes the final block.
    private func stream(_ counters: [(UInt64, UInt64)]) -> NettopStream {
        let s = NettopStream(launch: { nil })
        for (i, c) in counters.enumerated() {
            let t = Date(timeIntervalSince1970: Double(i) * 5)
            s.ingest(line: Self.header, at: t)
            s.ingest(line: "12:00:00.000001,x.77,\(c.0),\(c.1),", at: t)
        }
        s.ingest(line: Self.header, at: Date(timeIntervalSince1970: Double(counters.count) * 5))
        return s
    }

    @Test func parsesFixtureBlock() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/nettop-two-blocks.txt").path
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        let block = NettopParser.parseBlock(Array(lines[1..<4]))
        #expect(block.count == 3)
        #expect(block[101]?.bytesIn == 0 && block[101]?.bytesOut == 0)
        #expect(block[202]?.bytesIn == 2_620_529 && block[202]?.bytesOut == 7_151_871)
        #expect(block[303]?.bytesIn == 15 && block[303]?.bytesOut == 40)
    }

    @Test func nameWithDotsAndCommas() {
        let a = NettopParser.parseBlock(["12:00:00.000001,Foo Helper (Renderer).812,10,20,"])
        #expect(a[812]?.bytesIn == 10 && a[812]?.bytesOut == 20)
        let b = NettopParser.parseBlock(["12:00:00.000001,a,b.77,5,6,", "garbage"])
        #expect(b.count == 1 && b[77]?.bytesIn == 5 && b[77]?.bytesOut == 6)
    }

    @Test func ratesFromTwoBlocks() {
        let r = stream([(1000, 100), (6000, 600)]).rates(alive: [77: id(start: 1)])
        #expect(r[77]?.inPerSec == 1000)
        #expect(r[77]?.outPerSec == 100)
    }

    @Test func counterResetIsZero() {
        let r = stream([(6000, 100), (100, 50)]).rates(alive: [77: id(start: 1)])
        #expect(r[77]?.inPerSec == 0)
        #expect(r[77]?.outPerSec == 0)
    }

    @Test func fewerThanTwoBlocksIsEmpty() {
        #expect(stream([(1, 1)]).rates(alive: [77: id(start: 1)]).isEmpty)
    }

    @Test func reusedPidGetsNoRate() {
        let s = NettopStream(launch: { nil })
        func feed(_ i: Int, _ n: UInt64) {
            let t = Date(timeIntervalSince1970: Double(i) * 5)
            s.ingest(line: Self.header, at: t)
            s.ingest(line: "12:00:00.000001,x.77,\(n),\(n),", at: t)
        }
        feed(0, 1000)
        feed(1, 6000)
        feed(2, 7000)
        #expect(s.rates(alive: [77: id(start: 100)])[77] != nil)
        feed(3, 8000)
        #expect(s.rates(alive: [77: id(start: 200)])[77] == nil)
    }

    @Test func failedLaunchRetriesAndThenDelivers() throws {
        let pipe = Pipe()
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let s = NettopStream(retryDelay: 0.01) {
            let n = attempts.withLock { $0 += 1; return $0 }
            return n == 1 ? nil : NettopStream.Launched(handle: pipe.fileHandleForReading,
                                         terminate: { try? pipe.fileHandleForWriting.close() })
        }
        s.start()
        defer { s.stop() }
        for t in 0...2 {  // spaced writes give blocks distinct receive times
            pipe.fileHandleForWriting.write(Data("\(Self.header)\n12:00:00.000001,x.77,\(t * 100),0,\n".utf8))
            Thread.sleep(forTimeInterval: 0.05)
        }
        pipe.fileHandleForWriting.write(Data("\(Self.header)\n".utf8))
        let deadline = Date().addingTimeInterval(5)
        var r = s.rates(alive: [77: id(start: 1)])
        while r.isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            r = s.rates(alive: [77: id(start: 1)])
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(r[77] != nil)
    }
}
