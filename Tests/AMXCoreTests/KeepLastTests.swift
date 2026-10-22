import Testing
@testable import AMXCore

@Suite struct KeepLastTests {
    @Test func keepsNewestValues() {
        var values: [Double] = []
        for i in 1...70 { values.append(Double(i), keepingLast: 60) }
        #expect(values.count == 60)
        #expect(values.first == 11 && values.last == 70)
    }
}
