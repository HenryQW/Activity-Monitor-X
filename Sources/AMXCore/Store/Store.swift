import Foundation
import GRDB
import os

public struct StoreError: Error, CustomStringConvertible {
    public let path: String
    public let underlying: Error
    public var description: String { "\(path): \(underlying)" }
}

public enum Store {
    /// A corrupt database (or not a database) is set aside as `<path>.corrupt-<unix ts>` (with its `-wal` and `-shm`)
    /// and a new one is opened once, so the daemon does not exit and restart forever.
    public static func openWriter(path: String) throws -> DatabaseQueue {
        do {
            do {
                return try open(path: path)
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
                let aside = "\(path).corrupt-\(Int(Date().timeIntervalSince1970))"
                for suffix in ["", "-wal", "-shm"] {
                    do { try FileManager.default.moveItem(atPath: path + suffix, toPath: aside + suffix) } catch CocoaError.fileNoSuchFile {}
                }
                Logger(subsystem: AMX.daemonLabel, category: "store")
                    .error("database is corrupt (\(error.resultCode.rawValue, privacy: .public)); set aside as \(aside, privacy: .public), starting a new one")
                return try open(path: path)
            }
        } catch {
            throw StoreError(path: path, underlying: error)
        }
    }

    private static func open(path: String) throws -> DatabaseQueue {
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        let queue = try DatabaseQueue(path: path, configuration: config)
        // auto_vacuum only takes effect before the first table exists.
        try queue.writeWithoutTransaction { db in
            if try Int.fetchOne(db, sql: "PRAGMA page_count") == 0 {
                try db.execute(sql: "PRAGMA auto_vacuum=INCREMENTAL")
            }
            try db.execute(sql: "PRAGMA journal_mode=WAL")
        }
        try Schema.migrator.migrate(queue)
        return queue
    }

    /// `prepare` runs on each new connection, e.g. `AgentSQL.views`.
    public static func openReader(path: String, prepare: (@Sendable (Database) throws -> Void)? = nil) throws -> DatabasePool {
        var config = Configuration()
        config.readonly = true
        config.busyMode = .timeout(5)
        if let prepare { config.prepareDatabase(prepare) }
        return try DatabasePool(path: path, configuration: config)
    }
}
