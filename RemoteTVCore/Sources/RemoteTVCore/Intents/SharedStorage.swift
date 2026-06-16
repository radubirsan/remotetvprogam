import Foundation

/// Storage shared between the app and the Control Center widget extension.
///
/// A control's button intent runs in the **widget extension's** process, which has its own
/// container — it can't see the app's `UserDefaults.standard` or default Keychain items. An
/// **App Group** bridges that gap. Until the App Group capability is enabled on both targets
/// (Xcode → Signing & Capabilities → App Groups), `UserDefaults(suiteName:)` simply returns a
/// process-local suite, so the app keeps working and the controls just won't see the active TV
/// yet — no crash, graceful degradation.
public enum SharedStorage {
    /// Must match the `com.apple.security.application-groups` entry in BOTH the app's and the
    /// extension's entitlements, and be registrable by this team — so it shares the
    /// `ro.remotetv` namespace as the bundle ids (`com.remotetv` isn't ours, which is also why
    /// the bundle ids were rebranded). Token + active-device sharing both ride this group.
    public static let appGroupID = "group.ro.remotetv.RemoteTV"

    /// Unused: the pairing token is shared via the App Group (``AppGroupTokenStore`` /
    /// ``MirroringTokenStore``), so no Keychain Sharing entitlement is required. Kept `nil`.
    public static let keychainAccessGroup: String? = nil

    /// The active-TV JSON key — the same string `RootView`'s `@AppStorage` uses. `RootView`
    /// mirror-writes into the App Group suite so the extension can read the last device
    /// (including its MAC) without any live connection.
    public static let lastRemoteDeviceKey = "lastRemoteDeviceJSON"

    /// App Group defaults when the capability is on, else a usable fallback.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The last TV the app controlled, as persisted JSON, or `nil`.
    public static var lastRemoteDeviceJSON: String? {
        let shared = defaults.string(forKey: lastRemoteDeviceKey)
        if let shared, !shared.isEmpty { return shared }
        // Fall back to the app's standard suite for the pre-App-Group case (and for the
        // in-app/Siri path, which already reads standard defaults).
        let standard = UserDefaults.standard.string(forKey: lastRemoteDeviceKey)
        return (standard?.isEmpty == false) ? standard : nil
    }

    /// Mirror the active device into the shared suite. Called by `RootView` whenever it
    /// persists or clears the active TV, so the controls always target the current TV.
    public static func setLastRemoteDeviceJSON(_ json: String) {
        defaults.set(json, forKey: lastRemoteDeviceKey)
    }
}
