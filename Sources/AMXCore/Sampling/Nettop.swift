import Foundation
import os

public enum NettopParser {
    /// Parses data rows (header excluded). Row: `time,<name>.<pid>,<in>,<out>,`; the name may contain commas.
    public static func parseBlock(_ lines: [Substring]) -> [Int32: (bytesIn: UInt64, bytesOut: UInt64)] {
        var out: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        for line in lines {
            var f = line.split(separator: ",", omittingEmptySubsequences: false)
            if f.last?.isEmpty == true { f.removeLast() }
            guard f.count >= 4, let bytesOut = UInt64(f[f.count - 1]), let bytesIn = UInt64(f[f.count - 2])
            else { continue }
            let name = f[1..<(f.count - 2)].joined(separator: ",")
            guard let dot = name.lastIndex(of: "."), let pid = Int32(name[name.index(after: dot)...]) else { continue }
            out[pid] = (bytesIn, bytesOut)
        }
        return out
    }
}

/// One long-running `nettop`; blocks of cumulative per-pid counters arrive every 5 s.
public final class NettopStream: @unchecked Sendable {
    private typealias Counters = [Int32: (bytesIn: UInt64, bytesOut: UInt64)]
    private static let header = "time,,bytes_in,bytes_out,"

    public struct Launched {
        let handle: FileHandle
        let terminate: () -> Void
        let keepAlive: Any?  // objects that must outlive the launch, e.g. nettop's stdin pipe
        public init(handle: FileHandle, keepAlive: Any? = nil, terminate: @escaping () -> Void) {
            self.handle = handle
            self.keepAlive = keepAlive
            self.terminate = terminate
        }
    }

    private static let log = Logger(subsystem: "com.henryqw.activitymonitorx.daemon", category: "nettop")
    private let launch: () -> Launched?
    private let retryDelay: TimeInterval
    private let lock = NSLock()
    private var generation = 0
    private var running = false
    private var active: Launched?
    private var current: (at: Date, rows: [Substring])?
    private var complete: [(at: Date, counters: Counters)] = []  // last two complete blocks
    private var previousAlive: [Int32: ProcessIdentity] = [:]

    public init(retryDelay: TimeInterval = 2, launch: @escaping () -> Launched? = NettopStream.launchNettop) {
        self.launch = launch
        self.retryDelay = retryDelay
    }

    /// Returns nil when nettop cannot start; the caller retries.
    public static func launchNettop() -> Launched? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-x", "-J", "bytes_in,bytes_out", "-L", "0", "-s", "5"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        let stdin = Pipe()  // nettop spins at 100%+ CPU when stdin is at EOF (/dev/null under launchd)
        p.standardInput = stdin
        do { try p.run() } catch {
            log.error("cannot launch nettop: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return Launched(handle: pipe.fileHandleForReading, keepAlive: stdin, terminate: { p.terminate() })
    }

    public func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        generation += 1
        let gen = generation
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in readLoop(gen) }
    }

    public func stop() {
        lock.lock()
        running = false
        generation += 1
        let a = active
        lock.unlock()
        a?.terminate()  // EOF follows; the reader closes its own handle
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == gen
    }

    private func readLoop(_ gen: Int) {
        while isCurrent(gen) {
            if let l = launch() {
                lock.lock()
                let ok = generation == gen
                if ok { active = l }
                lock.unlock()
                guard ok else {
                    l.terminate()
                    try? l.handle.close()
                    return
                }
                var buffer = Data()
                while isCurrent(gen), case let chunk = l.handle.availableData, !chunk.isEmpty {
                    buffer.append(chunk)
                    while isCurrent(gen), let nl = buffer.firstIndex(of: 0x0A) {
                        ingest(line: String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self), at: Date())
                        buffer.removeSubrange(buffer.startIndex...nl)
                    }
                }
                l.terminate()
                try? l.handle.close()
                lock.lock()
                if generation == gen {
                    active = nil
                    current = nil  // a partial block must not pair with the next run
                }
                lock.unlock()
            }
            guard isCurrent(gen) else { return }
            Thread.sleep(forTimeInterval: retryDelay)
        }
    }

    func ingest(line: String, at time: Date) {
        lock.lock()
        defer { lock.unlock() }
        if line == Self.header {
            if let c = current {
                complete.append((c.at, NettopParser.parseBlock(c.rows)))
                if complete.count > 2 { complete.removeFirst() }
            }
            current = (time, [])
        } else if !line.isEmpty {
            current?.rows.append(Substring(line))
        }
    }

    /// Bytes per second since the previous block. A pid not alive, or whose identity changed since the
    /// previous call, gets no rate.
    public func rates(alive: [Int32: ProcessIdentity]) -> [Int32: (inPerSec: Double, outPerSec: Double)] {
        lock.lock()
        defer { lock.unlock() }
        let before = previousAlive
        previousAlive = alive
        guard complete.count == 2 else { return [:] }
        let (old, new) = (complete[0], complete[1])
        let dt = new.at.timeIntervalSince(old.at)
        guard dt > 0 else { return [:] }
        var out: [Int32: (inPerSec: Double, outPerSec: Double)] = [:]
        for (pid, now) in new.counters {
            guard let was = old.counters[pid], let id = alive[pid], before[pid].map({ $0 == id }) ?? true
            else { continue }
            out[pid] = (Double(now.bytesIn >= was.bytesIn ? now.bytesIn - was.bytesIn : 0) / dt,
                        Double(now.bytesOut >= was.bytesOut ? now.bytesOut - was.bytesOut : 0) / dt)
        }
        return out
    }
}
