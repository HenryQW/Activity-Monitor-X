import GRDB

public enum Schema {
    static let procMetrics = ["cpu", "mem", "disk_r", "disk_w", "energy", "gpu", "net_in", "net_out"]
    static let sysMetrics = ["cpu", "mem_used", "mem_compressed", "swap_used", "pressure_level",
                             "pressure_pct", "thermal_state", "load1", "disk_r", "disk_w", "disk_iops",
                             "disk_lat_ms", "disk_util", "gpu", "temp_cpu", "temp_gpu", "temp_ssd",
                             "net_in", "net_out"]
    private static let sysIntegers: Set = ["mem_used", "mem_compressed", "swap_used", "pressure_level", "thermal_state"]
    static let maxOnly: Set = ["pressure_level", "thermal_state"]

    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "processes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pid", .integer).notNull()
                t.column("start_time", .double).notNull()
                t.column("name", .text).notNull()
                t.column("path", .text)
                t.column("app_path", .text)
                t.column("app_name", .text)
                t.column("bundle_id", .text)
                t.column("team_id", .text)
                t.column("uid", .integer)
                t.column("translated", .integer).notNull().defaults(to: 0)
                t.column("first_seen", .double).notNull()
                t.column("last_seen", .double).notNull()
                t.uniqueKey(["pid", "start_time"])
            }
            try db.create(index: "idx_processes_last_seen", on: "processes", columns: ["last_seen"])

            try db.execute(sql: """
                CREATE TABLE process_samples(
                  process_id INTEGER NOT NULL REFERENCES processes(id) ON DELETE CASCADE,
                  ts REAL NOT NULL, cpu REAL, mem INTEGER, disk_r REAL, disk_w REAL, energy REAL,
                  gpu REAL, net_in REAL, net_out REAL, PRIMARY KEY(process_id, ts)) WITHOUT ROWID
                """)
            try db.create(index: "idx_process_samples_ts", on: "process_samples", columns: ["ts"])

            for tier in ["minute", "hour"] {
                let table = "process_\(tier)"
                try db.create(table: table) { t in
                    t.column("process_id", .integer).notNull()
                    t.column("bucket", .double).notNull()
                    t.column("samples", .integer).notNull()
                    for c in procMetrics {
                        t.column("\(c)_avg", .double)
                        t.column("\(c)_max", .double)
                    }
                    t.primaryKey(["process_id", "bucket"])
                }
                try db.create(index: "idx_\(table)_bucket", on: table, columns: ["bucket"])
            }

            try db.create(table: "system_samples") { t in
                t.column("ts", .double).primaryKey()
                for c in sysMetrics { t.column(c, sysIntegers.contains(c) ? .integer : .double) }
            }
            for tier in ["minute", "hour"] {
                let table = "system_\(tier)"
                try db.create(table: table) { t in
                    t.column("bucket", .double).primaryKey()
                    t.column("samples", .integer).notNull()
                    for c in sysMetrics {
                        if !maxOnly.contains(c) { t.column("\(c)_avg", .double) }
                        t.column("\(c)_max", .double)
                    }
                }
            }

            try db.create(table: "events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ts", .double).notNull()
                t.column("kind", .text).notNull()
                t.column("severity", .integer).notNull()
                t.column("process_id", .integer).references("processes", onDelete: .setNull)
                t.column("rule", .text)
                t.column("message", .text).notNull()
                t.column("value", .double)
            }
            try db.create(index: "idx_events_ts", on: "events", columns: ["ts"])

            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .double).notNull()
            }
        }
        return m
    }
}
