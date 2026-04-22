import Foundation

/// A TV found via Bonjour/mDNS discovery on the local network.
///
/// Keyed by UDN (sourced from the `u` field of the `_samsungmsf._tcp` TXT record) because the
/// UPnP Unique Device Name is stable across reboots and DHCP renewals, while IP is not. The
/// ``DiscoveryViewModel`` uses `udn` to dedupe live responses.
struct DiscoveredTV: Sendable, Identifiable, Hashable {
    var id: String { udn }
    let ip: String
    let friendlyName: String
    let modelName: String
    let udn: String
}
