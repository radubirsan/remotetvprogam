//
//  RemoteTVExtensionControl.swift
//  RemoteTVExtension
//
//  Self-contained Control Center / Lock Screen control that wakes the Samsung TV.
//
//  It deliberately depends on NO app-target code: the extension uses a file-system
//  synchronized group (it compiles whatever is in this folder), and the app's networking
//  stack isn't a member of this target. A Wake-on-LAN packet is small and the protocol is
//  stable, so it's reproduced inline here — mirroring `UDPBroadcastWakeService` /
//  `MagicPacketBuilder` in the app. (Full power *toggle* and mute need the live WebSocket
//  stack, which would require sharing that code via a Swift package — a follow-up.)
//

import AppIntents
import Darwin
import SwiftUI
import WidgetKit

// MARK: - Control

struct WakeTVControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.wake"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WakeTVControlIntent()) {
                Label("Wake TV", systemImage: "power")
            }
        }
        .displayName("Wake TV")
        .description("Wake your Samsung TV with a Wake-on-LAN signal.")
    }
}

// MARK: - Intent

struct WakeTVControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Wake TV"
    static let description = IntentDescription(
        "Sends a Wake-on-LAN signal to the last Samsung TV you used."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let device = SharedTVDevice.last() else {
            throw WakeControlError.noTVConfigured
        }
        guard let mac = device.mac, !mac.isEmpty else {
            throw WakeControlError.macUnknown
        }
        try WakeOnLAN.send(mac: mac, ip: device.ip)
        return .result(dialog: "Sent a wake signal to \(device.name).")
    }
}

enum WakeControlError: Error, CustomLocalizedStringResourceConvertible {
    case noTVConfigured
    case macUnknown
    case sendFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTVConfigured:
            "No TV is set up yet. Open RemoteTV and connect to your TV once first."
        case .macUnknown:
            "This TV's network address isn't on file yet. Connect once while it's on, then waking will work."
        case .sendFailed:
            "Couldn't send the wake signal."
        }
    }
}

// MARK: - Shared device (read from the App Group)

/// The minimal slice of the app's `TVDevice` the control needs. Decoded from the same
/// `lastRemoteDeviceJSON` the app mirror-writes into the App Group suite (`RootView` →
/// `SharedStorage`). Unknown keys (`mode`) are ignored by the synthesized decoder.
private struct SharedTVDevice: Decodable {
    let ip: String
    let name: String
    let mac: String?

    /// Must match `SharedStorage.appGroupID` / `.lastRemoteDeviceKey` in the app.
    static let appGroupID = "group.com.remotetv.RemoteTV"
    static let key = "lastRemoteDeviceJSON"

    static func last() -> SharedTVDevice? {
        let json = UserDefaults(suiteName: appGroupID)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SharedTVDevice.self, from: data)
    }
}

// MARK: - Wake-on-LAN (inline, mirrors UDPBroadcastWakeService)

private enum WakeOnLAN {
    /// Sends the magic packet to the limited broadcast, the TV's unicast IP, and the /24
    /// subnet-directed broadcast, on ports 7 and 9, across a few bursts — the combination
    /// that reliably wakes a sleeping Samsung Wi-Fi NIC.
    static func send(mac: String, ip: String?) throws {
        let packet = try magicPacket(mac: mac)
        var addresses = ["255.255.255.255"]
        if let ip, !ip.isEmpty {
            if !addresses.contains(ip) { addresses.append(ip) }
            let parts = ip.split(separator: ".")
            if parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) {
                let subnet = "\(parts[0]).\(parts[1]).\(parts[2]).255"
                if !addresses.contains(subnet) { addresses.append(subnet) }
            }
        }

        var anySent = false
        for _ in 0..<3 {
            for address in addresses {
                for port in [UInt16(7), 9] where (try? sendPacket(packet, to: address, port: port)) != nil {
                    anySent = true
                }
            }
        }
        guard anySent else { throw WakeControlError.sendFailed }
    }

    /// 6 bytes of 0xFF followed by the 6-byte MAC repeated 16 times (102 bytes).
    static func magicPacket(mac: String) throws -> Data {
        let cleaned = mac.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard cleaned.count == 12, cleaned.allSatisfy(\.isHexDigit) else {
            throw WakeControlError.macUnknown
        }
        var bytes = Data(capacity: 6)
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw WakeControlError.macUnknown
            }
            bytes.append(byte)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(bytes) }
        return packet
    }

    static func sendPacket(_ packet: Data, to address: String, port: UInt16) throws {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { throw WakeControlError.sendFailed }
        defer { close(sock) }

        var enable: Int32 = 1
        guard setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw WakeControlError.sendFailed
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
            throw WakeControlError.sendFailed
        }

        let sent = packet.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buffer.baseAddress, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw WakeControlError.sendFailed }
    }
}
