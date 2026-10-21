import AMXCore
import Foundation
import GRDB

private let tables = ["processes", "process_samples", "process_minute", "process_hour",
                      "system_samples", "system_minute", "system_hour", "events", "meta"]

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: amx ping\n       amx stats [--db <path>]\n".utf8))
    exit(64)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("amx: \(message)\n".utf8))
    exit(1)
}

func ping() -> Never {
    let connection = NSXPCConnection(machServiceName: AMX.daemonLabel, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: DaemonXPC.self)
    connection.resume()
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        fail("cannot reach amxd (\(AMX.daemonLabel)): \(error.localizedDescription)")
    } as! DaemonXPC
    proxy.ping { json in
        print(json)
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { fail("ping timed out after 5 s") }
    dispatchMain()
}

func stats(path: String) -> Never {
    do {
        try Store.openReader(path: path).read { db in
            for table in tables {
                print("\(table) \(try Table(table).fetchCount(db))")
            }
            let size = try Int.fetchOne(db, sql: "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()")!
            print("size_bytes \(size)")
        }
    } catch {
        fail("\(error)")
    }
    exit(0)
}

var args = CommandLine.arguments.dropFirst()
switch args.popFirst() {
case "ping":
    guard args.isEmpty else { usage() }
    ping()
case "stats":
    var path = AMX.databasePath
    while let arg = args.popFirst() {
        guard arg == "--db", let value = args.popFirst() else { usage() }
        path = value
    }
    stats(path: path)
default:
    usage()
}
