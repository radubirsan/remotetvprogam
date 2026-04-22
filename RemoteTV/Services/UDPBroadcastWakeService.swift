import Foundation
import Darwin

/// Sends Wake-on-LAN magic packets over UDP using BSD sockets.
///
/// Samsung Tizen TVs on Wi-Fi stop processing the limited broadcast (`255.255.255.255`) after a
/// few seconds of sleep — the NIC powers down to the DTIM-beacon listen schedule and ignores
/// limited broadcasts. They do still wake for **directed subnet broadcasts** (e.g.
/// `192.168.1.255`) and sometimes for unicast packets addressed to their last-known IP (while
/// the AP's ARP entry remains cached).
///
/// This service targets all three — limited broadcast, subnet-directed broadcast, and unicast —
/// on both port 7 and port 9 (both are WOL-conventional), across several bursts ~200ms apart.
///
/// `NWConnection` doesn't expose `SO_BROADCAST` for directed broadcasts, so this uses POSIX
/// sockets (`socket`/`setsockopt`/`sendto`) directly via the `Darwin` module.
struct UDPBroadcastWakeService: WakeOnLANService {
    private let burstCount: Int
    private let interBurstDelay: Duration
    private let ports: [UInt16]

    init(
        burstCount: Int = 5,
        interBurstDelay: Duration = .milliseconds(200),
        ports: [UInt16] = [7, 9]
    ) {
        self.burstCount = burstCount
        self.interBurstDelay = interBurstDelay
        self.ports = ports
    }

    func wake(mac: String, ip: String?) async throws {
        let packet = try MagicPacketBuilder.packet(for: mac)
        let addresses = addressesForWake(ip: ip)

        var anySent = false
        var lastError: Error?

        for burst in 0..<burstCount {
            for address in addresses {
                for port in ports {
                    do {
                        try sendPacket(packet, to: address, port: port)
                        anySent = true
                    } catch {
                        lastError = error
                    }
                }
            }
            if burst < burstCount - 1 {
                try? await Task.sleep(for: interBurstDelay)
            }
        }

        if !anySent, let lastError { throw lastError }
    }

    /// Destinations targeted for each burst. Kept in the order {limited-broadcast, unicast,
    /// subnet-broadcast}. Duplicates are filtered so we don't send the same packet twice when
    /// `ip` can't be parsed into a sensible subnet.
    private func addressesForWake(ip: String?) -> [String] {
        var result: [String] = ["255.255.255.255"]
        if let ip, !ip.isEmpty {
            if !result.contains(ip) { result.append(ip) }
            if let subnet = subnetBroadcast(for: ip), !result.contains(subnet) {
                result.append(subnet)
            }
        }
        return result
    }

    /// Assumes a /24 prefix — the overwhelming default on home networks. For non-/24 setups
    /// the unicast send still covers the TV.
    private func subnetBroadcast(for ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard
            parts.count == 4,
            parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false })
        else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }

    private func sendPacket(_ packet: Data, to address: String, port: UInt16) throws {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            throw TVServiceError.wakeOnLANFailure("socket() failed (errno \(errno))")
        }
        defer { close(sock) }

        var enable: Int32 = 1
        guard setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw TVServiceError.wakeOnLANFailure("setsockopt SO_BROADCAST failed (errno \(errno))")
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
            throw TVServiceError.wakeOnLANFailure("inet_pton failed for \(address)")
        }

        let bytesSent = packet.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buffer.baseAddress, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard bytesSent == packet.count else {
            throw TVServiceError.wakeOnLANFailure("sendto() to \(address):\(port) returned \(bytesSent) (errno \(errno))")
        }
    }
}
