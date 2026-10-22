import Foundation
import Testing
@testable import AMXCore

@Suite struct OpenFilesTests {
    @Test func socketsToDisplay() {
        var tcp = OpenFiles.Socket(family: AF_INET, type: SOCK_STREAM)
        tcp.local = [127, 0, 0, 1]
        tcp.localPort = 8080
        tcp.remote = [10, 0, 0, 2]
        tcp.remotePort = 443
        tcp.tcpState = 4
        #expect(OpenFiles.item(tcp) == .socket(proto: "TCP", local: "127.0.0.1:8080", remote: "10.0.0.2:443", state: "Established"))
        var listen = OpenFiles.Socket(family: AF_INET6, type: SOCK_STREAM)
        listen.local = [UInt8](repeating: 0, count: 16)
        listen.localPort = 22
        listen.tcpState = 1
        #expect(OpenFiles.item(listen) == .socket(proto: "TCP", local: "*:22", remote: "*", state: "Listen"))
        var udp = OpenFiles.Socket(family: AF_INET6, type: SOCK_DGRAM)
        udp.local = [UInt8](repeating: 0, count: 15) + [1]
        udp.localPort = 5353
        #expect(OpenFiles.item(udp) == .socket(proto: "UDP", local: "[::1]:5353", remote: "*", state: ""))
        var unix = OpenFiles.Socket(family: AF_UNIX, type: SOCK_STREAM)
        #expect(OpenFiles.item(unix) == nil)
        unix.unixPath = "/var/run/x.sock"
        #expect(OpenFiles.item(unix) == .socket(proto: "Unix", local: "/var/run/x.sock", remote: "", state: ""))
        #expect(OpenFiles.item(OpenFiles.Socket(family: AF_SYSTEM, type: SOCK_RAW)) == nil)
    }

    @Test func cappedDropsRepeatsAndCountsTheRest() {
        let items = (0..<(OpenFiles.limit + 20)).map { OpenItem.file(path: "/f\($0)") }
        let out = OpenFiles.capped(pid: 7, [.file(path: "/f0")] + items)
        #expect(out.pid == 7 && out.items.count == OpenFiles.limit && out.more == 20)
        #expect(out.items.first == .file(path: "/f0") && out.items[1] == .file(path: "/f1"))
        #expect(OpenFiles.capped(pid: 7, [.file(path: "/a")]).more == 0)
        #expect(OpenFiles.capped(pid: 7, [.file(path: "/f0")] + items, unread: 30).more == 50)
    }

    @Test func requestIsValidatedAtTheBoundary() throws {
        let one = [ProcessIdentity(pid: 5, startTime: 1.5)]
        #expect(OpenFiles.request(try JSONEncoder().encode(one)) == one)
        let many = (1...Int32(OpenFiles.maxProcesses + 1)).map { ProcessIdentity(pid: $0, startTime: 0) }
        #expect(OpenFiles.request(try JSONEncoder().encode(many)) == nil)
        #expect(OpenFiles.request(try JSONEncoder().encode([ProcessIdentity(pid: 0, startTime: 0)])) == nil)
        #expect(OpenFiles.request(Data("{}".utf8)) == nil)
    }

    @Test func readsOwnOpenFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amx-open-\(UUID().uuidString)")
        try Data().write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let items = try #require(OpenFiles.read(pid: getpid())).items
        // The kernel gives the real path (/private/var/…).
        #expect(items.contains { if case .file(let path) = $0 { path.hasSuffix(url.path) } else { false } })
    }
}
