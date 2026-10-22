import Foundation
import GRDB
@testable import AMXCore

/// Two hours of three processes, an hour of system samples, three events and two groups. Safari is open.
enum AgentFixture {
    static let now = 1_792_656_000.0
    static let device = Device(cores: 10, memory: 17_179_869_184)

    static func make() throws -> (AgentContext, DatabasePool) {
        let path = NSTemporaryDirectory() + "amx-\(UUID().uuidString).sqlite"
        let writer = try Store.openWriter(path: path)
        func process(_ name: String, path: String, app: (path: String, name: String)?, bundle: String?,
                     team: String? = nil, open: Bool = false) -> ProcessRecord {
            ProcessRecord(id: nil, pid: 0, startTime: now - 7200, name: name, path: path, appPath: app?.path,
                          appName: app?.name, bundleId: bundle, teamId: team, uid: 501, translated: false,
                          firstSeen: now - 7200, lastSeen: open ? Schema.open : now - 1)
        }
        let processes: [(ProcessRecord, cpu: Double, mem: Int64)] = [
            (process("Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari",
                     app: ("/Applications/Safari.app", "Safari"), bundle: "com.apple.Safari", open: true),
             40, 2_147_483_648),
            (process("Code Helper", path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper",
                     app: ("/Applications/Visual Studio Code.app", "Visual Studio Code"), bundle: "com.microsoft.VSCode",
                     team: "UBF8T346G9"),
             20, 1_073_741_824),
            (process("mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores", app: nil, bundle: nil),
             10, 536_870_912),
        ]
        try writer.write { db in
            var mds: Int64 = 0, safari: Int64 = 0
            for (i, (record, cpu, mem)) in processes.enumerated() {
                var record = record
                record.pid = Int32(100 + i)
                try record.insert(db)
                let id = db.lastInsertedRowID
                if record.name == "mds_stores" { mds = id }
                if record.name == "Safari" { safari = id }
                for t in stride(from: now - 7200, to: now, by: 60) {
                    try db.execute(sql: """
                        INSERT INTO process_minute(bucket, process_id, samples, cpu_avg, cpu_max, mem_avg, mem_max)
                        VALUES (?, ?, 12, ?, ?, ?, ?)
                        """, arguments: [t, id, cpu, cpu, mem, mem])
                    if t >= now - 3600 { try ProcessSampleRecord(processId: id, ts: t, cpu: cpu, mem: mem).insert(db) }
                }
            }
            for t in stride(from: now - 3600, to: now, by: 60) {
                let spike = t == now - 1800
                try SystemSampleRecord(ts: t, cpu: spike ? 90 : 30, pressureLevel: spike ? 2 : 1, thermalState: 0).insert(db)
            }
            try EventRecord(ts: now - 1800, kind: "pressure", severity: 1, processId: mds, message: "Memory pressure warning").insert(db)
            try EventRecord(ts: now - 900, kind: "thermal", severity: 1, message: "Thermal state fair").insert(db)
            try EventRecord(ts: now - 600, kind: "alert", severity: 1, processId: safari, rule: "sustained_cpu",
                            message: "Safari used 100 % CPU for 5 min").insert(db)
        }
        let pool = try Store.openReader(path: path, prepare: AgentSQL.views)
        let groups = [
            ProcessGroup(name: "Dev", rule: .condition(GroupCondition(field: .teamID, op: .equals, value: "UBF8T346G9"))),
            ProcessGroup(name: "Browsers", rule: .condition(GroupCondition(field: .bundleID, op: .startsWith,
                                                                           value: "com.apple.safari"))),
        ]
        return (AgentContext(pool: pool, groups: { groups }, device: device, now: { AgentFixture.now }), pool)
    }
}
