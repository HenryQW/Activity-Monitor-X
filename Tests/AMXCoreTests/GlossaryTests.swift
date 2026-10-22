import Foundation
import Testing
@testable import AMXCore

@Suite struct GlossaryTests {
    private func glossary(_ entries: [(title: String, match: String)]) throws -> Glossary {
        let items = entries.map { #"{"title":"\#($0.title)","description":"","category":"app","match":{\#($0.match)}}"# }
        return try JSONDecoder().decode(Glossary.self, from: Data(#"{"version":1,"entries":[\#(items.joined(separator: ","))]}"#.utf8))
    }

    @Test func lookupOrder() throws {
        let g = try glossary([
            ("NP", #""namePattern":"helper""#), ("PP", #""pathPrefix":"/System/""#), ("BP", #""bundleIDPrefix":"com.y""#),
            ("N", #""name":"agent""#), ("C", #""pathPattern":"/X.framework/""#), ("S", #""pathSuffix":"/Helpers/agent""#),
            ("P", #""path":"/usr/bin/log""#), ("B", #""bundleID":"com.x""#),
        ])
        func title(_ name: String, _ bundle: String? = nil, _ path: String? = nil) -> String? {
            g.lookup(name: name, bundleID: bundle, path: path)?.title
        }
        #expect(title("agent", "com.x", "/usr/bin/log") == "B")
        #expect(title("log", nil, "/usr/bin/log") == "P")
        #expect(title("agent", nil, "/x/Helpers/agent") == "S")
        #expect(title("agent", nil, "/Library/X.framework/Versions/A/agent") == "C")
        #expect(title("agent", nil, "/opt/agent") == "N")
        #expect(title("zz", "com.y.z") == "BP")
        #expect(title("zz", nil, "/System/zz") == "PP")
        #expect(title("My Helper") == "NP")
        #expect(title("zz") == nil)
    }

    @Test func longestPrefixWins() throws {
        let g = try glossary([("Any", #""bundleIDPrefix":"com.""#), ("Google", #""bundleIDPrefix":"com.google.""#)])
        #expect(g.lookup(name: "x", bundleID: "com.google.Chrome", path: nil)?.title == "Google")
    }

    @Test func nameFromPathFallback() throws {
        let g = try glossary([("WebContent", #""name":"com.apple.WebKit.WebContent""#)])
        let path = "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent"
        #expect(g.lookup(name: "com.apple.WebKi", bundleID: nil, path: path)?.title == "WebContent")
    }

    @Test func bundledFileDecodes() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Packaging/glossary.json")
        let g = try JSONDecoder().decode(Glossary.self, from: Data(contentsOf: url))
        #expect(g.entries.count == 711)
        #expect(!g.entries.contains { $0.title.contains("Mac Performance Monitor") || $0.description.contains("Mac Performance Monitor") })
        #expect(g.lookup(name: "kernel_task", bundleID: nil, path: nil)?.expectedHigh == true)
    }
}
