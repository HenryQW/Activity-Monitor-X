import Foundation
import GRDB
import Testing
@testable import AMXCore

/// Replays amxd's write path on a temp DB: one `SampleWriter.write` per 5 s tick, a flush and `Rollup.run`
/// every 12 ticks, a TRUNCATE checkpoint every `AMX.ticksPerCheckpoint`. Counts what SQLite writes to disk:
/// the WAL bytes, plus one page for each distinct page a checkpoint copies into the DB file. On the live
/// install this count (WAL growth plus distinct pages) gave 325 KB/s against the 340 KB/s macOS reported.
///
/// Load (measured on the live install): ~1,500 live processes, 1,160 long-lived (63 busy, the rest idle),
/// ~2,700 new processes per hour that live 1 to 15 min; ~36 raw rows/s.
private final class DiskWriteSim {
    private struct Proc {
        let new: (RawProcess, AppInfo, teamID: String?)
        var busyTicks: Int
        let diesAt: Int
        let mem: UInt64
    }

    let path = NSTemporaryDirectory() + "amx-disk-\(UUID().uuidString).sqlite"
    let db: DatabaseQueue
    private let writer: SampleWriter
    private let policy: RetentionPolicy
    var attribute: Bool
    private var procs: [Proc] = []
    private var spawned: [(RawProcess, AppInfo, teamID: String?)] = []
    private var nextPid: Int32 = 100
    private var tick = 0
    private var seed: UInt64 = 1
    private let start = 1_800_000_000.0

    private(set) var walBytes = 0
    private(set) var checkpointBytes = 0
    private(set) var rollupWalBytes = 0
    /// Per b-tree (dbstat name; "?" is page 1, pointer-map and freelist pages): WAL frames and checkpointed pages.
    private(set) var frames: [String: Int] = [:]
    private(set) var copied: [String: Int] = [:]
    /// WAL frames written by `Rollup.run`, per b-tree.
    private(set) var rollupFrames: [String: Int] = [:]
    /// WAL frame ranges written by `Rollup.run` since the last checkpoint.
    private var rollupRanges: [Range<Int>] = []
    var checkpointEvery = AMX.ticksPerCheckpoint
    var newPerHour = 2700
    var live: Int { procs.count }

    init(policy: RetentionPolicy = RetentionPolicy(), attribute: Bool = false,
         ticksPerCommit: Int = AMX.ticksPerCommit) throws {
        db = try Store.openWriter(path: path)
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_autocheckpoint=0") }
        writer = try SampleWriter(db: db, path: path, ticksPerCommit: ticksPerCommit)
        self.policy = policy
        self.attribute = attribute
        for i in 0..<1160 { spawn(diesAt: .max, busy: i < 63 ? .max : 0) }
        for _ in 0..<340 { spawn(diesAt: Int(random() % 180), busy: 0) }
    }

    private func random() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func spawn(diesAt: Int, busy: Int) {
        nextPid += 1
        let name = "process\(nextPid)"
        let app = "/Applications/App\(nextPid % 120).app"
        let raw = RawProcess(identity: ProcessIdentity(pid: nextPid, startTime: start + Double(tick) * 5),
                             name: name, path: "\(app)/Contents/Frameworks/Helper.framework/Versions/A/\(name)",
                             uid: 501, cpuNanos: 0, footprint: 0, diskRead: 0, diskWritten: 0, wakeups: 0,
                             translated: false)
        let new = (raw, AppInfo(appPath: app, appName: "App\(nextPid % 120)", bundleID: "com.example.app\(nextPid % 120)"),
                   teamID: "ABCDE12345" as String?)
        procs.append(Proc(new: new, busyTicks: busy, diesAt: diesAt, mem: 10_000_000 + random() % 500_000_000))
        spawned.append(new)
    }

    func run(minutes: Int) throws {
        for _ in 0..<(minutes * 12) { try step() }
    }

    func resetCounters() {
        (walBytes, checkpointBytes, rollupWalBytes, frames, copied, rollupFrames) = (0, 0, 0, [:], [:], [:])
    }

    private func step() throws {
        let now = start + Double(tick) * 5
        for _ in 0..<((tick + 1) * newPerHour / 720 - tick * newPerHour / 720) {
            spawn(diesAt: tick + 12 + Int(random() % 168), busy: 3)
        }
        let samples = procs.indices.map { i -> ProcessSample in
            let busy = procs[i].busyTicks > 0
            procs[i].busyTicks -= 1
            return ProcessSample(identity: procs[i].new.0.identity, cpu: busy ? Double(random() % 5000) / 100 : 0.1,
                                 mem: procs[i].mem + (busy ? random() % 4_000_000 : 0), diskR: 0,
                                 diskW: busy ? Double(random() % 100_000) : 0, energy: 0, gpu: 0, netIn: 0, netOut: 0)
        }
        try writer.write(now: now, processes: samples, newProcesses: spawned, system: SystemSample())
        spawned = []
        tick += 1
        procs.removeAll { $0.diesAt <= tick }
        if tick % 12 == 0 {
            let before = walSize()
            try writer.flush()
            try Rollup.run(db: db, now: now, policy: policy)
            rollupWalBytes += walSize() - before
            rollupRanges.append(max(0, (before - 32) / 4120)..<max(0, (walSize() - 32) / 4120))
        }
        if tick % checkpointEvery == 0 { try checkpoint() }
    }

    private func walSize() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path + "-wal")[.size] as? Int) ?? 0
    }

    private func checkpoint() throws {
        let wal = try [UInt8](Data(contentsOf: URL(fileURLWithPath: path + "-wal")))
        func u32(_ o: Int) -> Int { wal[o..<o + 4].reduce(0) { $0 << 8 | Int($1) } }
        var pages: [Int: Int] = [:], rollupPages: [Int: Int] = [:]
        if wal.count >= 32 {
            let pageSize = u32(8)
            var off = 32
            while off + 24 + pageSize <= wal.count, wal[off + 8..<off + 16] == wal[16..<24] {
                pages[u32(off), default: 0] += 1
                let frame = (off - 32) / (24 + pageSize)
                if rollupRanges.contains(where: { $0.contains(frame) }) { rollupPages[u32(off), default: 0] += 1 }
                off += 24 + pageSize
            }
            walBytes += wal.count
            checkpointBytes += pages.count * pageSize
        }
        if attribute {
            let owner = try db.read { db in
                Dictionary(try Row.fetchAll(db, sql: "SELECT pageno, name FROM dbstat").map { ($0[0] as Int, $0[1] as String) },
                           uniquingKeysWith: { a, _ in a })
            }
            for (page, n) in pages {
                frames[owner[page] ?? ((page - 2) % 820 == 0 ? "?ptrmap" : "?free"), default: 0] += n
                copied[owner[page] ?? ((page - 2) % 820 == 0 ? "?ptrmap" : "?free"), default: 0] += 1
            }
            for (page, n) in rollupPages { rollupFrames[owner[page] ?? ((page - 2) % 820 == 0 ? "?ptrmap" : "?free"), default: 0] += n }
        }
        rollupRanges = []
        try db.writeWithoutTransaction { _ = try Row.fetchOne($0, sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
    }

    func count(_ table: String) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! }
    }
}

@Suite struct DiskWriteTests {
    /// macOS flags amxd above ~24 KB/s of disk writes averaged over a day.
    @Test func realisticLoadWritesUnder20KBPerSecond() throws {
        var policy = RetentionPolicy()
        policy.raw = 600
        let sim = try DiskWriteSim(policy: policy)
        try sim.run(minutes: 10)
        sim.resetCounters()
        try sim.run(minutes: 20)
        let perSecond = Double(sim.walBytes + sim.checkpointBytes) / 1200
        #expect(perSecond <= 20 * 1024, "\(Int(perSecond)) B/s")
    }

    /// Detailed report:
    /// `AMX_DISK_BENCH=<warmup min>,<measured min>[,<cache KiB>[,<ticks per checkpoint>[,<ticks per commit>
    /// [,<new processes per hour>]]]]] make test`. Raw retention is the warmup, so retention deletes run in the
    /// measured window.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMX_DISK_BENCH"] != nil))
    func bench() throws {
        let args = ProcessInfo.processInfo.environment["AMX_DISK_BENCH"]!.split(separator: ",").map { Int($0)! }
        let (warmup, minutes) = (args[0], args[1])
        var policy = RetentionPolicy()
        policy.raw = Double(max(warmup, 10) * 60)
        let sim = try DiskWriteSim(policy: policy, ticksPerCommit: args.count > 4 ? args[4] : AMX.ticksPerCommit)
        if args.count > 2 { try sim.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA cache_size=-\(args[2])") } }
        if args.count > 3 { sim.checkpointEvery = args[3] }
        if args.count > 5 { sim.newPerHour = args[5] }
        try sim.run(minutes: warmup)
        sim.resetCounters()
        sim.attribute = true
        let rows = try sim.count("process_samples")
        let clock = ContinuousClock(), t = clock.now
        try sim.run(minutes: minutes)
        let seconds = Double(minutes * 60)
        func kbps(_ b: Int) -> String { String(format: "%.1f KB/s", Double(b) / 1024 / seconds) }
        print("""
            DISKBENCH warmup \(warmup) min, measured \(minutes) min in \(clock.now - t): \
            total \(kbps(sim.walBytes + sim.checkpointBytes)) (WAL \(kbps(sim.walBytes)), \
            checkpoint \(kbps(sim.checkpointBytes)), rollup WAL \(kbps(sim.rollupWalBytes))); \
            raw rows \(rows) -> \(try sim.count("process_samples")), processes \(try sim.count("processes")) \
            (\(sim.live) live), \
            minute rows \(try sim.count("process_minute")), \
            pages \(try sim.db.read { try Int.fetchOne($0, sql: "PRAGMA page_count")! }), \
            free \(try sim.db.read { try Int.fetchOne($0, sql: "PRAGMA freelist_count")! })
            """)
        for (name, n) in sim.frames.sorted(by: { $0.value > $1.value }) where n * 4120 > Int(seconds) * 50 {
            print("""
                DISKBENCH   \(name): WAL \(kbps(n * 4120)) (rollup \(kbps(sim.rollupFrames[name, default: 0] * 4120))), \
                checkpoint \(kbps(sim.copied[name]! * 4096))
                """)
        }
    }
}
