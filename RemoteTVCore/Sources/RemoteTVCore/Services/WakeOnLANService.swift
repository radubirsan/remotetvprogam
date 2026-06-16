import Foundation

/// Abstracts sending a Wake-on-LAN magic packet so the UI layer can power a TV on.
///
/// `ip` is the TV's last-known IPv4 address; used for unicast delivery and to compute a directed
/// subnet broadcast (e.g. `192.168.1.255`), which reaches Samsung TVs in deep sleep when the
/// limited broadcast (`255.255.255.255`) does not.
public protocol WakeOnLANService: Sendable {
    func wake(mac: String, ip: String?) async throws
}
