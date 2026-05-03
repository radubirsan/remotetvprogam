import Testing
import Foundation
@testable import TVScheduel

@Suite("XMLTVDate parsing")
struct XMLTVDateTests {

    @Test("Parses canonical timestamp with timezone")
    func parsesCanonicalTimestamp() {
        let date = XMLTVDate.parse("20260503060000 +0200")
        #expect(date != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 3)
        #expect(components.hour == 6)
        #expect(components.minute == 0)
    }

    @Test("Treats missing timezone as UTC")
    func missingTimezoneIsUTC() {
        let date = XMLTVDate.parse("20260101120000")
        #expect(date != nil)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .hour], from: date!)
        #expect(components.year == 2026)
        #expect(components.hour == 12)
    }

    @Test("Parses negative offsets")
    func parsesNegativeOffset() {
        let date = XMLTVDate.parse("20260101120000 -0500")
        #expect(date != nil)
        // 12:00 -05:00 == 17:00 UTC
        let utcComponents = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date!)
        #expect(utcComponents.hour == 17)
    }

    @Test("Returns nil for garbage input")
    func rejectsGarbage() {
        #expect(XMLTVDate.parse("") == nil)
        #expect(XMLTVDate.parse("not a date") == nil)
        #expect(XMLTVDate.parse("2026") == nil)
    }
}
