import Testing
@testable import AMXCore

@Suite struct SidebarOrderTests {
    let defaults = ["a", "b", "c"]

    @Test func emptySavedGivesDefaults() {
        #expect(SidebarOrder.merge(saved: [], defaults: defaults) == defaults)
    }

    @Test func keepsSavedOrderAndDropsUnknown() {
        #expect(SidebarOrder.merge(saved: ["c", "x", "a", "b"], defaults: defaults) == ["c", "a", "b"])
    }

    @Test func newIdIsAppended() {
        #expect(SidebarOrder.merge(saved: ["b", "a"], defaults: defaults) == ["b", "a", "c"])
    }

    @Test func duplicatesAreRemoved() {
        #expect(SidebarOrder.merge(saved: ["b", "b", "a", "a"], defaults: defaults) == ["b", "a", "c"])
    }
}
