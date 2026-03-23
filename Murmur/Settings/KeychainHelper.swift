import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.murmur.app"
    private static let account = "openai-api-key"

    /// Base query attributes shared across all operations.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
    }

    @discardableResult
    static func save(apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        let query = baseQuery

        // Try update first
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // If not found, add
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    static func loadAPIKey() -> String? {
        // 1. Try Data Protection keychain
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // 2. Try legacy keychain (no Data Protection flag) and migrate if found
        if let legacyKey = loadFromLegacyKeychain() {
            save(apiKey: legacyKey)
            deleteFromLegacyKeychain()
            return legacyKey
        }

        return nil
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        SecItemDelete(baseQuery as CFDictionary) == errSecSuccess
    }

    static func hasAPIKey() -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Legacy keychain migration helpers

    private static var legacyBaseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadFromLegacyKeychain() -> String? {
        var query = legacyBaseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromLegacyKeychain() {
        SecItemDelete(legacyBaseQuery as CFDictionary)
    }
}
