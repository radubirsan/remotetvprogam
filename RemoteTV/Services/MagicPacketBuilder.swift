import Foundation

/// Builds the 102-byte Wake-on-LAN magic packet: 6 bytes of `0xFF` followed by the target
/// MAC address repeated 16 times.
enum MagicPacketBuilder {
    /// Builds the magic packet for `mac` (accepts `AA:BB:CC:DD:EE:FF`, `AA-BB-…`, or `AABBCC…`).
    ///
    /// - Throws: ``TVServiceError/wakeOnLANFailure(_:)`` if the MAC can't be parsed as six bytes.
    static func packet(for mac: String) throws -> Data {
        let bytes = try macBytes(from: mac)
        var packet = Data(capacity: 102)
        packet.append(contentsOf: Array(repeating: UInt8(0xFF), count: 6))
        for _ in 0..<16 {
            packet.append(bytes)
        }
        return packet
    }

    /// Parses `AA:BB:CC:DD:EE:FF` / `AA-BB-…` / `AABBCCDDEEFF` into 6 bytes.
    static func macBytes(from mac: String) throws -> Data {
        let cleaned = mac
            .replacing(":", with: "")
            .replacing("-", with: "")
            .uppercased()

        guard cleaned.count == 12, cleaned.allSatisfy(\.isHexDigit) else {
            throw TVServiceError.wakeOnLANFailure("Invalid MAC address: \(mac)")
        }

        var bytes = Data(capacity: 6)
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw TVServiceError.wakeOnLANFailure("Invalid MAC address: \(mac)")
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
