import Foundation
import GRDB
import SQLite3

/// The read-only SQL tool and the TEMP views it documents.
public enum AgentSQL {
    static let maxRows = 1000
    static let timeLimit = 10.0

    private static let app = "COALESCE(p.app_name, p.name) AS app, COALESCE(p.app_path, p.name) AS app_key"
    private static let tiers = [("v_raw", "process_samples"), ("v_minute", "process_minute"), ("v_hour", "process_hour")]

    /// Creates the TEMP views on each new connection: pass to `Store.openReader(prepare:)`.
    @Sendable public static func views(_ db: Database) throws {
        var sql = """
            CREATE TEMP VIEW v_process AS
            SELECT p.id, p.pid, p.start_time, p.name, p.path, p.app_path, p.app_name, p.bundle_id, p.team_id, p.uid,
                   p.translated, p.first_seen,
                   \(Schema.lastSeenSQL) AS last_seen,
                   \(app)
            FROM processes p;
            """
        for (view, table) in tiers {
            sql += """
                CREATE TEMP VIEW \(view) AS
                SELECT t.*, p.pid, p.name, \(app), p.bundle_id, p.team_id FROM \(table) t JOIN processes p ON p.id = t.process_id;
                """
        }
        try db.execute(sql: sql)
    }

    struct Arguments: Decodable { let sql: String }

    /// A cell as JSON: blobs as base64, non-finite numbers as null.
    struct Cell: Encodable {
        let value: DatabaseValue

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch value.storage {
            case .null: try c.encodeNil()
            case .int64(let i): try c.encode(i)
            case .double(let d): if d.isFinite { try c.encode(d) } else { try c.encodeNil() }
            case .string(let s): try c.encode(s)
            case .blob(let data): try c.encode(data.base64EncodedString())
            }
        }
    }

    struct Result: Encodable { let columns: [String]; let rows: [[Cell]]; let truncated: Bool }

    private static let metrics = Schema.procMetrics.joined(separator: ", ")

    static let query = AgentTools.Tool(
        "query",
        """
        Runs one read-only SQLite statement on the history database. At most \(maxRows) rows; truncated is true \
        when more matched. A query stops after \(Int(timeLimit)) s. Blobs read as base64, non-finite numbers as null. \
        Times are Unix seconds. \
        Tables: processes(id, pid, start_time, name, path, app_path, app_name, bundle_id, team_id, uid, translated, \
        first_seen, last_seen): last_seen is +inf while a process lives; it reads as null here. \
        process_samples(ts, process_id, \(metrics)): raw samples. \
        process_minute and process_hour(bucket, process_id, samples, and <metric>_avg, <metric>_max for each of \
        \(metrics)). Process rows are sparse: a missing row means the last value held. \
        system_samples(ts, \(Schema.sysMetrics.joined(separator: ", "))); system_minute and system_hour(bucket, \
        samples, <metric>_avg and <metric>_max; \(Schema.maxOnly.sorted().joined(separator: " and ")) have _max only). \
        events(id, ts, kind, severity, process_id, rule, message, value). \
        Views: v_process is processes with last_seen of a live process mapped to the start of the last recorded \
        minute, plus app (app_name, else name) and app_key (app_path, else name). v_raw, v_minute and v_hour are \
        process_samples, process_minute and process_hour rows plus pid, name, app, app_key, bundle_id, team_id. \
        Units: process cpu % of one core, system cpu % of all cores; mem, mem_used, mem_compressed, swap_used bytes; \
        disk_r, disk_w, net_in, net_out bytes/s; energy energy impact; gpu % GPU; disk_iops ops/s; \
        disk_lat_ms ms per operation; disk_util % busy of the busiest disk; disk_free bytes free on the startup volume, purgeable not included.
        """,
        schema: AgentTools.schema([#""sql":{"type":"string"}"#], required: ["sql"])
    ) { (a: Arguments, context) -> Result in
        try context.pool.read { try run(a.sql, $0) }
    }

    static func run(_ sql: String, _ db: Database, limit: Double = timeLimit) throws -> Result {
        // PRAGMA setters pass isReadonly and act at prepare time on the pooled connection: refuse them unprepared.
        guard ["SELECT", "WITH", "VALUES"].contains(firstKeyword(sql)) else {
            throw AgentError.invalid("query must be a SELECT, WITH or VALUES statement")
        }
        sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_ATTACHED, 0)
        sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_LENGTH, 1_000_000)
        var deadline = ProcessInfo.processInfo.systemUptime + limit
        do {
            return try withUnsafeMutablePointer(to: &deadline) { deadline in
                // A non-zero return interrupts the statement.
                sqlite3_progress_handler(db.sqliteConnection, 1000, {
                    ProcessInfo.processInfo.systemUptime > $0!.load(as: Double.self) ? 1 : 0
                }, deadline)
                defer { sqlite3_progress_handler(db.sqliteConnection, 0, nil, nil) }
                let statement = try db.makeStatement(sql: firstStatement(sql, db))
                guard statement.isReadonly else { throw AgentError.invalid("query must be read-only") }
                let cursor = try Row.fetchCursor(statement)
                var rows: [[Cell]] = []
                while let row = try cursor.next() {
                    if rows.count == maxRows { return Result(columns: statement.columnNames, rows: rows, truncated: true) }
                    rows.append(row.databaseValues.map(Cell.init))
                }
                return Result(columns: statement.columnNames, rows: rows, truncated: false)
            }
        } catch let error as DatabaseError {
            if error.resultCode == .SQLITE_INTERRUPT {
                throw AgentError.invalid("query took longer than \(String(format: "%g", limit)) s")
            }
            throw AgentError.invalid(error.message ?? "\(error.resultCode)")
        }
    }

    /// The first word after whitespace and comments, uppercased.
    private static func firstKeyword(_ sql: String) -> String {
        let b = Array(sql.utf8)
        return String(decoding: b[skipBlank(b, from: 0)...].prefix { (0x61...0x7A).contains($0 | 0x20) }, as: UTF8.self)
            .uppercased()
    }

    /// The text of the first statement. SQLite runs PRAGMA setters at prepare time, so the text after it is never
    /// prepared: it may hold only whitespace, comments and `;`.
    private static func firstStatement(_ sql: String, _ db: Database) throws -> String {
        let b = Array(sql.utf8)
        let end = try sql.withCString { start in
            var statement: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            let code = sqlite3_prepare_v2(db.sqliteConnection, start, -1, &statement, &tail)
            sqlite3_finalize(statement)
            guard code == SQLITE_OK else {
                throw DatabaseError(resultCode: ResultCode(rawValue: code),
                                    message: String(cString: sqlite3_errmsg(db.sqliteConnection)))
            }
            return tail! - start
        }
        guard skipBlank(b, from: end, semicolons: true) == b.count else {
            throw AgentError.invalid("query must be one statement")
        }
        return String(decoding: b[..<end], as: UTF8.self)
    }

    /// The index after whitespace and comments from `i`, read as SQLite's tokenizer reads them.
    private static func skipBlank(_ b: [UInt8], from start: Int, semicolons: Bool = false) -> Int {
        var i = start
        while i < b.count {
            if [0x20, 0x09, 0x0A, 0x0C, 0x0D].contains(b[i]) || (semicolons && b[i] == 0x3B) {
                i += 1
            } else if b[i...].starts(with: "--".utf8) {
                while i < b.count && b[i] != 0x0A { i += 1 }
            } else if b[i...].starts(with: "/*".utf8) {
                i += 2
                while i < b.count && !b[i...].starts(with: "*/".utf8) { i += 1 }
                i = min(i + 2, b.count)
            } else {
                break
            }
        }
        return i
    }
}
