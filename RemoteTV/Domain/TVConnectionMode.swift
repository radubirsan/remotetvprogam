import Foundation

/// The websocket transport Samsung TVs expect depending on model year.
enum TVConnectionMode: String, CaseIterable, Identifiable, Sendable {
    /// `ws://<ip>:8001` — older models (roughly 2016–2018).
    case plain
    /// `wss://<ip>:8002` — 2019+ models. Requires trusting the TV's self-signed certificate.
    case secure

    var id: String { rawValue }

    var scheme: String { self == .secure ? "wss" : "ws" }

    var port: Int { self == .secure ? 8002 : 8001 }
}
