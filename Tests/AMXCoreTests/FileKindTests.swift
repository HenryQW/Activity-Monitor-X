import Testing
@testable import AMXCore

@Suite struct FileKindTests {
    @Test func extensionWinsOverFolders() {
        #expect(FileKind.of(["Library", "Developer", "Notes.PDF"]) == .documents)
    }

    @Test func nearestFolderWins() {
        #expect(FileKind.of(["Library", "Caches", "data"]) == .system)
        #expect(FileKind.of(["Library", "Containers", "com.example", "Data"]) == .applications)
    }

    @Test func largestItemsComeBeforeFolders() {
        #expect(FileKind.of(["Library", "work"], largest: ["repo", "node_modules"]) == .developer)
        #expect(FileKind.of(["Library", "work"], largest: ["repo"]) == .system)
    }

    @Test func hiddenNameIsNotAnExtension() {
        #expect(FileKind.of(["Projects", ".git"]) == .developer)
    }

    @Test func noRuleIsOther() {
        #expect(FileKind.of(["Projects", "README"]) == .other)
        #expect(FileKind.of([]) == .other)
    }
}
