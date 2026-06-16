import Foundation

/// Errors surfaced by the TV transport layer. Kept equatable so views can drive UI off state.
public enum TVServiceError: Error, Sendable, Equatable {
    case invalidIP
    case invalidURL
    case notConnected
    /// The stored pairing token was rejected by the TV — caller should delete it and retry.
    case tokenRejected
    /// The user declined the pairing prompt on the TV.
    case pairingRejected
    case pairingTimeout
    case webSocketFailure(String)
    case keychainFailure(Int32)
    /// Failure from the Wake-on-LAN transport (bad MAC or UDP send error).
    case wakeOnLANFailure(String)
    /// The `GET http://<ip>:8001/api/v2/` device-info probe failed (bad response, missing fields).
    case deviceInfoFailure(String)
    /// The `POST /api/v2/applications/<appId>` app launch failed (TV rejected or network error).
    case appLaunchFailure(String)
    /// No MAC address is on file for this TV yet — user must connect at least once while the TV is on.
    case macAddressUnknown
    /// The TV never sent `ms.voiceApp.recording` after the voice key — Bixby didn't
    /// start listening (older firmware, or the voice key didn't take).
    case voiceNotReady
    /// Microphone access was denied — user must enable it in Settings.
    case microphoneDenied
    /// The microphone capture engine failed to start.
    case microphoneFailure(String)
}

extension Error {
    /// The message a view model should surface for this error: the curated
    /// ``TVServiceError`` copy when it is one, `localizedDescription` otherwise.
    /// Collapses the `catch TVServiceError / catch everything-else` pair that used
    /// to be copy-pasted around every `try await service.…` call site.
    public var displayMessage: String {
        (self as? TVServiceError)?.errorDescription ?? localizedDescription
    }
}

extension TVServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidIP: "Enter a valid IPv4 address (e.g. 192.168.1.42)."
        case .invalidURL: "Could not build a connection URL for this TV."
        case .notConnected: "Not connected to the TV."
        case .tokenRejected: "The saved pairing token was rejected. Try again to re-pair."
        case .pairingRejected: "Pairing was declined on the TV."
        case .pairingTimeout: "The TV didn't respond to the pairing request."
        case .webSocketFailure(let detail): "Connection failed: \(detail)"
        case .keychainFailure(let status): "Keychain error (\(status))."
        case .wakeOnLANFailure(let detail): "Wake-on-LAN failed: \(detail)"
        case .deviceInfoFailure(let detail): "Could not read TV info: \(detail)"
        case .appLaunchFailure(let detail): "Could not launch app: \(detail)"
        case .macAddressUnknown: "Connect to the TV at least once (while it's on) to capture its MAC."
        case .voiceNotReady: "The TV didn't start listening for voice. Try again."
        case .microphoneDenied: "Microphone access is off. Enable it in Settings → RemoteTV."
        case .microphoneFailure(let detail): "Couldn't start the microphone: \(detail)"
        }
    }
}
