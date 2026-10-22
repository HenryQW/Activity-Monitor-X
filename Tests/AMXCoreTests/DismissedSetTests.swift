import Testing
@testable import AMXCore

@Suite struct DismissedSetTests {
    @Test func keepsNewestWhenOverLimit() {
        let set = DismissedSet(ids: Array(1...Int64(DismissedSet.limit + 5)))
        #expect(set.ids.count == DismissedSet.limit)
        #expect(!set.contains(5) && set.contains(6) && set.contains(Int64(DismissedSet.limit + 5)))
    }

    @Test func duplicatesAndRestore() {
        var set = DismissedSet(ids: [3, 3, 4])
        #expect(set.ids == [3, 4])
        set.remove(3)
        #expect(!set.contains(3) && set.ids == [4])
    }
}
