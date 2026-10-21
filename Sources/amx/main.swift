import AMXCore
import Foundation
import GRDB

private let tables = ["processes", "process_samples", "process_minute", "process_hour",
                      "system_samples", "system_minute", "system_hour", "events", "meta"]

func usage() -> Never {
    FileHandle.standardError.write(Data("""
        usage: amx ping
               amx stats [--db <path>]
               amx tools
               amx call <tool> [<json-object>] [--db <path>] [--groups <path>]
               amx mcp [--db <path>] [--groups <path>]

        """.utf8))
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

func context(_ options: [String: String]) -> AgentContext {
    let groups = options["--groups"].map { URL(fileURLWithPath: $0) } ?? GroupStore.defaultURL
    do {
        let pool = try Store.openReader(path: options["--db"] ?? AMX.databasePath, prepare: AgentSQL.views)
        return AgentContext(pool: pool, groups: { try GroupStore.load(from: groups) })
    } catch {
        fail("\(error)")
    }
}

func call(_ tool: String, arguments: String, context: AgentContext) -> Never {
    do {
        print(String(decoding: try AgentTools.call(tool, arguments: Data(arguments.utf8), context: context), as: UTF8.self))
    } catch {
        fail("\(error)")
    }
    exit(0)
}

func mcp(context: AgentContext) -> Never {
    while let line = readLine() {
        guard let reply = MCPHandler.handle(line: line, context: context) else { continue }
        print(reply)
        fflush(stdout)
    }
    exit(0)
}

/// Splits `--db <path>` and `--groups <path>` from positional arguments.
func parse(_ args: ArraySlice<String>, options allowed: Set<String>) -> (positional: [String], options: [String: String]) {
    var (args, positional, options) = (args, [String](), [String: String]())
    while let arg = args.popFirst() {
        if allowed.contains(arg) {
            guard let value = args.popFirst() else { usage() }
            options[arg] = value
        } else {
            guard !arg.hasPrefix("--") else { usage() }
            positional.append(arg)
        }
    }
    return (positional, options)
}

var args = CommandLine.arguments.dropFirst()
switch args.popFirst() {
case "ping":
    guard args.isEmpty else { usage() }
    ping()
case "stats":
    let (positional, options) = parse(args, options: ["--db"])
    guard positional.isEmpty else { usage() }
    stats(path: options["--db"] ?? AMX.databasePath)
case "tools":
    guard args.isEmpty else { usage() }
    for spec in AgentTools.catalog {
        print("\(spec.name)\t\(spec.description.prefix { $0 != "\n" })")
    }
    exit(0)
case "call":
    let (positional, options) = parse(args, options: ["--db", "--groups"])
    guard (1...2).contains(positional.count) else { usage() }
    call(positional[0], arguments: positional.count == 2 ? positional[1] : "{}", context: context(options))
case "mcp":
    let (positional, options) = parse(args, options: ["--db", "--groups"])
    guard positional.isEmpty else { usage() }
    mcp(context: context(options))
default:
    usage()
}
