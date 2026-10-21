@testable import AMXCore
import Foundation
import Testing

@Suite struct AppAttributionTests {
    @Test func nestedHelperMapsToOuterApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let info = AppAttribution.app(forExecutable: helper, processName: "Google Chrome Helper (Renderer)")
        #expect(info.appPath == "/Applications/Google Chrome.app")
        #expect(info.appName == "Google Chrome")
    }

    @Test func plainBinaryIsOwnApp() {
        let info = AppAttribution.app(forExecutable: "/usr/libexec/mds_stores", processName: "mds_stores")
        #expect(info.appPath == nil)
        #expect(info.appName == "mds_stores")
        #expect(info.bundleID == nil)
    }

    @Test func nilPathUsesName() {
        #expect(AppAttribution.app(forExecutable: nil, processName: "kernel_task").appName == "kernel_task")
    }

    @Test func bundleIDReadFromPlist() {
        let info = AppAttribution.app(forExecutable: "/System/Applications/Calculator.app/Contents/MacOS/Calculator",
                                      processName: "Calculator")
        #expect(info.bundleID == "com.apple.calculator")
    }

    @Test func teamIDForAppleBinaryIsNil() {
        #expect(CodeSigning.teamID(forPath: "/bin/ls") == nil)
    }

    @Test func teamIDForUnsignedPathIsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CodeSigning.teamID(forPath: url.path) == nil)
    }
}
