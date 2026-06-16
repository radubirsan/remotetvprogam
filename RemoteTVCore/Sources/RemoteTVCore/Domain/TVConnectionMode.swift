import Foundation

/// The websocket transport Samsung TVs expect depending on model year.
public enum TVConnectionMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// `ws://<ip>:8001` — older models (roughly 2016–2018).
    case plain
    /// `wss://<ip>:8002` — 2019+ models. Requires trusting the TV's self-signed certificate.
    case secure

    public var id: String { rawValue }

    public var scheme: String { self == .secure ? "wss" : "ws" }

    public var port: Int { self == .secure ? 8002 : 8001 }
}
