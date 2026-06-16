import Foundation
import Security

/// Keychain-backed implementation of ``TVTokenStore``.
///
/// Wrapped in an `actor` so the synchronous `SecItem*` C APIs never block the main thread and
/// the non-`Sendable` CFDictionary arguments stay contained to this isolation domain.
public actor KeychainTVTokenStore: TVTokenStore {
    public static let service = "com.remotetv.samsung.token"

    /// When set, items are read/written under a shared Keychain access group so the
    /// Control Center widget extension can read the same pairing tokens. `nil` (the
    /// default) leaves every query exactly as before — the app's own behavior is
    /// unchanged until Keychain Sharing is enabled. Requires the `keychain-access-groups`
    /// entitlement on both targets.
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    /// Adds `kSecAttrAccessGroup` to a query when an access group is configured.
    private func scoped(_ query: [String: Any]) -> [String: Any] {
        guard let accessGroup else { return query }
        var scoped = query
        scoped[kSecAttrAccessGroup as String] = accessGroup
        return scoped
    }

    public func token(for ip: String) -> String? {
        let query = scoped([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: ip,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ])

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    public func save(_ token: String, for ip: String) throws {
        let data = Data(token.utf8)

        let query = scoped([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: ip
        ])

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            for (key, value) in attributes {
                addQuery[key] = value
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TVServiceError.keychainFailure(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw TVServiceError.keychainFailure(updateStatus)
        }
    }

    public func delete(for ip: String) throws {
        let query = scoped([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: ip
        ])
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TVServiceError.keychainFailure(status)
        }
    }
}
