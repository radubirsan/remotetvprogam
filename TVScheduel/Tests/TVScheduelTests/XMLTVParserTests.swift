import Testing
import Foundation
@testable import TVScheduel

@Suite("XMLTVParser")
struct XMLTVParserTests {

    @Test("Parses a small XMLTV document end to end")
    func parsesSmallDocument() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="digi24.ro">
            <display-name lang="ro">Digi 24</display-name>
            <icon src="https://example.com/digi24.png"/>
          </channel>
          <channel id="protv.ro">
            <display-name lang="ro">Pro TV</display-name>
            <display-name lang="en">Pro TV (RO)</display-name>
          </channel>
          <programme start="20260503060000 +0200" stop="20260503070000 +0200" channel="digi24.ro">
            <title lang="ro">Știrile Digi 24</title>
            <sub-title lang="ro">Ediție matinală</sub-title>
            <desc lang="ro">Buletin de știri.</desc>
            <category lang="ro">Știri</category>
          </programme>
          <programme start="20260503070000 +0200" stop="20260503080000 +0200" channel="digi24.ro">
            <title lang="ro">Jurnal Sport</title>
          </programme>
        </tv>
        """.data(using: .utf8)!

        let guide = try XMLTVParser.parse(xml)

        #expect(guide.channels.count == 2)
        #expect(guide.programmes.count == 2)

        let digi = try #require(guide.channels.first { $0.id == "digi24.ro" })
        #expect(digi.primaryName == "Digi 24")
        #expect(digi.iconURL?.absoluteString == "https://example.com/digi24.png")

        let protv = try #require(guide.channels.first { $0.id == "protv.ro" })
        #expect(protv.displayNames.count == 2)

        let news = try #require(guide.programmes.first)
        #expect(news.title == "Știrile Digi 24")
        #expect(news.subtitle == "Ediție matinală")
        #expect(news.description == "Buletin de știri.")
        #expect(news.categories == ["Știri"])
        #expect(news.channelID == "digi24.ro")
    }

    @Test("Drops programmes that are missing required fields")
    func skipsMalformedProgrammes() throws {
        let xml = """
        <tv>
          <channel id="x"><display-name>X</display-name></channel>
          <programme start="20260503060000 +0200" stop="20260503070000 +0200" channel="x">
            <title></title>
          </programme>
          <programme channel="x">
            <title>No times</title>
          </programme>
        </tv>
        """.data(using: .utf8)!

        let guide = try XMLTVParser.parse(xml)
        #expect(guide.programmes.isEmpty)
    }

    @Test("programmes(for:) sorts by start time")
    func programmesSorted() throws {
        let xml = """
        <tv>
          <channel id="x"><display-name>X</display-name></channel>
          <programme start="20260503080000 +0200" stop="20260503090000 +0200" channel="x">
            <title>Late</title>
          </programme>
          <programme start="20260503060000 +0200" stop="20260503070000 +0200" channel="x">
            <title>Early</title>
          </programme>
        </tv>
        """.data(using: .utf8)!

        let guide = try XMLTVParser.parse(xml)
        let titles = guide.programmes(for: "x").map(\.title)
        #expect(titles == ["Early", "Late"])
    }
}
