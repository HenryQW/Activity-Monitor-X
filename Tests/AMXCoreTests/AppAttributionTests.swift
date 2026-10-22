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

    private static let calculator = "/System/Applications/Calculator.app/Contents/MacOS/Calculator"
    private static let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"

    @Test func responsibleAppWins() {
        let info = AppAttribution.app(forExecutable: "/bin/zsh", processName: "zsh", responsiblePath: Self.calculator)
        #expect(info.appPath == "/System/Applications/Calculator.app")
        #expect(info.appName == "Calculator")
        #expect(info.bundleID == "com.apple.calculator")
    }

    @Test func terminalResponsibleFallsBackToPath() {
        let info = AppAttribution.app(forExecutable: "/bin/zsh", processName: "zsh", responsiblePath: Self.terminal)
        #expect(info.appPath == nil)
        #expect(info.appName == "zsh")
    }

    @Test func terminalKeepsOwnBundle() {
        let info = AppAttribution.app(forExecutable: Self.calculator, processName: "Calculator", responsiblePath: Self.terminal)
        #expect(info.appPath == "/System/Applications/Calculator.app")
    }

    @Test func customTerminalList() {
        let custom = AppAttribution.app(forExecutable: "/bin/zsh", processName: "zsh", responsiblePath: Self.calculator,
                                        terminals: ["com.apple.calculator"])
        #expect(custom.appPath == nil)
        #expect(custom.appName == "zsh")
        let standard = AppAttribution.app(forExecutable: "/bin/zsh", processName: "zsh", responsiblePath: Self.calculator,
                                          terminals: AppAttribution.defaultTerminalBundleIDs)
        #expect(standard.appName == "Calculator")
    }

    @Test func responsibleOutsideBundleUsesPath() {
        let info = AppAttribution.app(forExecutable: "/bin/zsh", processName: "zsh", responsiblePath: "/usr/sbin/sshd")
        #expect(info.appPath == nil)
        #expect(info.appName == "zsh")
    }

    @Test func exitedResponsibleIsNil() {
        #expect(Responsibility.responsiblePath(of: 999_999) == nil)
    }

    @Test func teamIDForAppleBinaryIsNil() {
        #expect(CodeSigning.teamID(forPath: "/bin/ls") == nil)
    }

    @Test func sealedVolumeSkipsOnlySystemPaths() {
        #expect(CodeSigning.onSealedVolume("/usr/libexec/x"))
        #expect(CodeSigning.onSealedVolume("/System/Library/x"))
        #expect(!CodeSigning.onSealedVolume("/usr/local/bin/x"))
        #expect(!CodeSigning.onSealedVolume("/System/Volumes/Data/Applications/X.app/Contents/MacOS/X"))
        #expect(!CodeSigning.onSealedVolume("/Applications/X.app/Contents/MacOS/X"))
    }

    @Test func teamIDForUnsignedPathIsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CodeSigning.teamID(forPath: url.path) == nil)
    }
}
