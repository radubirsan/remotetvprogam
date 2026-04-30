import Foundation

/// What the TV reported the last time we polled `GET /api/v2/`. Distinct from
/// ``TVConnectionState`` — the WebSocket can stay connected while the TV is in
/// standby, so the UI needs both axes to render correctly (e.g. the status LED
/// goes dim grey for "connected to a TV that's currently off" rather than the
/// solid green of a fully active TV).
///
/// Values are derived from Samsung's `device.PowerState` field on the REST info
/// endpoint. `unknown` covers both "not polled yet" and "last poll failed".
enum TVPowerState: String, Sendable, Equatable {
    case unknown
    case on
    case off
}
