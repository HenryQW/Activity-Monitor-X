import GRDB

public struct StoreError: Error, CustomStringConvertible {
    public let path: String
    public let underlying: Error
    public var description: String { "\(path): \(underlying)" }
}

public enum Store {
    public static func openWriter(path: String) throws -> DatabaseQueue {
        do {
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
        } catch {
            throw StoreError(path: path, underlying: error)
        }
    }

    public static func openReader(path: String) throws -> DatabasePool {
        var config = Configuration()
        config.readonly = true
        config.busyMode = .timeout(5)
        return try DatabasePool(path: path, configuration: config)
    }
}
