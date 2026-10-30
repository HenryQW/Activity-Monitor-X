import AMXCore
import Foundation
import os

var dbPath = AMX.databasePath
var xpc = true
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--db":
        guard let value = args.popFirst() else { usage() }
        dbPath = value
    case "--no-xpc":
        xpc = false
    default:
        usage()
    }
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: amxd [--db <path>] [--no-xpc]\n".utf8))
    exit(64)
}

do {
    try Daemon(dbPath: dbPath, xpc: xpc).run()
} catch {
    // launchd keeps no standard error for the bundled helper (D91): the unified log has the reason.
    Logger(subsystem: AMX.daemonLabel, category: "main").fault("amxd: \(String(describing: error), privacy: .public)")
    FileHandle.standardError.write(Data("amxd: \(error)\n".utf8))
    exit(1)
}
