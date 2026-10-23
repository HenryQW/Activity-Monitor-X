import Foundation
import Testing
@testable import AMXCore

@Suite struct ZoneLabelTests {
    private let hongKong = TimeZone(identifier: "Asia/Hong_Kong")!
    /// 22 Oct 2026, noon UTC: New York and Los Angeles are on summer time.
    private let now = Date(timeIntervalSince1970: 1_792_670_400)

    @Test func systemTimeIsItsAbbreviationOnly() {
        #expect(ZoneLabel.title(forced: nil, system: hongKong, at: now) == "HKT")
    }

    @Test func aForcedZoneAddsItsDifferenceFromSystemTime() {
        let zone = { TimeZone(identifier: $0)! }
        #expect(ZoneLabel.title(forced: zone("America/Los_Angeles"), system: hongKong, at: now) == "PDT, 15 h behind")
        #expect(ZoneLabel.title(forced: zone("Asia/Tokyo"), system: hongKong, at: now) == "JST, 1 h ahead")
        #expect(ZoneLabel.title(forced: zone("UTC"), system: hongKong, at: now) == "UTC, 8 h behind")
        #expect(ZoneLabel.title(forced: zone("Asia/Kolkata"), system: hongKong, at: now) == "IST, 2.5 h behind")
        // The same offset as system time needs no difference.
        #expect(ZoneLabel.title(forced: zone("Asia/Singapore"), system: hongKong, at: now) == "SGT")
    }

    @Test func summerTimeChangesTheAbbreviationAndTheDifference() {
        let newYork = TimeZone(identifier: "America/New_York")!, winter = Date(timeIntervalSince1970: 1_798_000_000)
        #expect(ZoneLabel.abbreviation(newYork, at: now) == "EDT" && ZoneLabel.abbreviation(newYork, at: winter) == "EST")
        #expect(ZoneLabel.difference(of: newYork, from: hongKong, at: now) == "12 h behind")
        #expect(ZoneLabel.difference(of: newYork, from: hongKong, at: winter) == "13 h behind")
    }
}
