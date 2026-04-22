import Foundation
import Testing
@testable import RemoteTV

struct MagicPacketBuilderTests {
    @Test func packetIs102Bytes() throws {
        let packet = try MagicPacketBuilder.packet(for: "AA:BB:CC:DD:EE:FF")
        #expect(packet.count == 102)
    }

    @Test func packetStartsWithSixFFBytes() throws {
        let packet = try MagicPacketBuilder.packet(for: "AA:BB:CC:DD:EE:FF")
        #expect(Array(packet.prefix(6)) == Array(repeating: UInt8(0xFF), count: 6))
    }

    @Test func packetRepeatsMACSixteenTimes() throws {
        let packet = try MagicPacketBuilder.packet(for: "AA:BB:CC:DD:EE:FF")
        let mac: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            let slice = Array(packet[start..<(start + 6)])
            #expect(slice == mac, "Repetition \(repetition) should equal the MAC bytes")
        }
    }

    @Test(arguments: [
        "AA:BB:CC:DD:EE:FF",
        "aa:bb:cc:dd:ee:ff",
        "AA-BB-CC-DD-EE-FF",
        "AABBCCDDEEFF"
    ])
    func acceptsCommonMACFormats(_ mac: String) throws {
        let packet = try MagicPacketBuilder.packet(for: mac)
        #expect(packet.count == 102)
    }

    @Test(arguments: [
        "",
        "AA:BB:CC",
        "AA:BB:CC:DD:EE",
        "GG:BB:CC:DD:EE:FF",
        "AA:BB:CC:DD:EE:FF:00",
        "not a mac"
    ])
    func rejectsInvalidMAC(_ mac: String) {
        #expect(throws: TVServiceError.self) {
            _ = try MagicPacketBuilder.packet(for: mac)
        }
    }

    @Test func macBytesParsesCorrectly() throws {
        let bytes = try MagicPacketBuilder.macBytes(from: "01:23:45:67:89:AB")
        #expect(Array(bytes) == [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
    }
}
