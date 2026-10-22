import Foundation
import Testing
@testable import AMXCore

@Suite struct DiskScannerTests {
    /// A fresh temp folder per test; files hold written bytes (not sparse).
    private final class Folder {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("amx-scan-\(UUID().uuidString)").path
        init() { try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(atPath: path) }

        func write(_ name: String, _ bytes: Int) {
            let url = URL(fileURLWithPath: path + "/" + name)
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(repeating: 7, count: bytes).write(to: url)
        }

        /// Allocated bytes of the entries, from `lstat`.
        func allocated(_ names: String...) -> UInt64 {
            names.reduce(0) { sum, name in
                var st = stat()
                precondition(lstat(name.isEmpty ? path : path + "/" + name, &st) == 0)
                return sum + UInt64(st.st_blocks) * 512
            }
        }
    }

    private static let mib = 1 << 20

    @Test func foldersSumAllocatedSizes() throws {
        let f = Folder()
        f.write("a/x", 2 * Self.mib)
        f.write("a/b/y", 3 * Self.mib)
        f.write("z", 3 * Self.mib / 2)
        let tree = try DiskScanner.scan(f.path)
        #expect(tree.root.size == f.allocated("", "a", "a/x", "a/b", "a/b/y", "z"))
        #expect(tree.root.children.map(\.name) == ["a", "z"])
        #expect(tree.root.children[0].size == f.allocated("a/x") + f.allocated("a/b", "a/b/y"))
    }

    @Test func hardLinkCountedOnce() throws {
        let f = Folder()
        f.write("a/f", 2 * Self.mib)
        try FileManager.default.createDirectory(atPath: f.path + "/b", withIntermediateDirectories: false)
        #expect(link(f.path + "/a/f", f.path + "/b/f") == 0)
        let tree = try DiskScanner.scan(f.path)
        #expect(tree.root.size == f.allocated("a/f"))
    }

    @Test func symlinkNotFollowed() throws {
        let f = Folder()
        f.write("real/data", 4 * Self.mib)
        try FileManager.default.createSymbolicLink(atPath: f.path + "/link", withDestinationPath: f.path + "/real")
        let tree = try DiskScanner.scan(f.path)
        #expect(tree.root.size == f.allocated("real/data", "link"))
    }

    @Test func refusedFolderIsListed() throws {
        let f = Folder()
        f.write("a/x", 2 * Self.mib)
        try FileManager.default.createDirectory(atPath: f.path + "/c", withIntermediateDirectories: false)
        chmod(f.path + "/c", 0o000)
        defer { chmod(f.path + "/c", 0o755) }
        let tree = try DiskScanner.scan(f.path)
        #expect(tree.refused == [f.path + "/c"])
        #expect(tree.refusedCount == 1)
        #expect(tree.root.children.contains { $0.name == "c" && $0.kind == .refused })
        #expect(tree.root.size == f.allocated("a/x"))
    }

    @Test func smallItemsFold() throws {
        let f = Folder()
        for i in 0..<120 { f.write("big\(i)", 3 * Self.mib / 2) }
        for i in 0..<30 { f.write("small\(i)", 4096) }
        let tree = try DiskScanner.scan(f.path)
        #expect(tree.root.children.filter { $0.kind == .file }.count == 100)
        let smaller = tree.root.children.filter { $0.kind == .smaller }
        #expect(smaller.map(\.items) == [50])
        let names = (0..<120).map { "big\($0)" } + (0..<30).map { "small\($0)" }
        #expect(tree.root.size == names.reduce(0) { $0 + f.allocated($1) })
    }

    @Test func nodeCapIsHard() throws {
        let f = Folder()
        for i in 0..<60 {
            f.write("d\(i)/1", 3 * Self.mib / 2)
            f.write("d\(i)/2", 3 * Self.mib / 2)
        }
        var limits = DiskScanLimits()
        limits.maxNodes = 40
        let capped = try DiskScanner.scan(f.path, limits: limits)
        let full = try DiskScanner.scan(f.path)
        #expect(capped.root.count <= 40)
        #expect(capped.simplified)
        #expect(capped.root.size == full.root.size)
    }

    @Test func capCountsLiveNodes() throws {
        let f = Folder()
        for i in 0..<500 { f.write("d\(i)/f", 4096) }
        f.write("big/f", 2 * Self.mib)
        var limits = DiskScanLimits()
        limits.maxNodes = 40
        let tree = try DiskScanner.scan(f.path, limits: limits)
        let big = tree.root.children.first { $0.name == "big" }
        #expect(big?.children.contains { $0.kind == .file } == true)
    }

    @Test func stopGivesPartial() throws {
        let f = Folder()
        for i in 0..<3_000 { f.write("d\(i % 10)/f\(i)", 1) }
        var calls = 0
        let tree = try DiskScanner.scan(f.path, shouldStop: { calls += 1; return calls >= 2 })
        #expect(tree.partial)
        #expect(tree.root.items < 3_000)
        func sumsHold(_ node: DiskTree.Node) -> Bool {
            node.kind != .folder || (node.size == node.children.reduce(0) { $0 + $1.size } && node.children.allSatisfy(sumsHold))
        }
        #expect(sumsHold(tree.root))
    }

    /// Unattended real check (no TCC prompt): `/Applications` against `du`.
    @Test func applicationsMatchesDu() throws {
        let du = Process()
        du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        du.arguments = ["-sk", "/Applications"]
        let pipe = Pipe()
        du.standardOutput = pipe
        du.standardError = FileHandle.nullDevice
        try du.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        du.waitUntilExit()
        let expected = Double(try #require(UInt64(out.prefix { $0.isNumber }))) * 1024
        let tree = try DiskScanner.scan("/Applications")
        #expect(abs(Double(tree.root.size) - expected) <= expected * 0.02)
    }
}
