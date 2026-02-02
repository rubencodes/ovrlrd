import Foundation
import Security

enum KeychainService {
    private static let service = "com.ovrlrd.app"

    enum Key: String {
        case sessionToken
        case deviceToken
        case tokenExpiry // ISO8601 date string
        case apiKey
    }

    /// Save a value to the keychain
    /// - Returns: true if save succeeded, false otherwise
    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        // Delete any existing item first (ignore status - may not exist)
        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data

        let status = SecItemAdd(newQuery as CFDictionary, nil)

        if status != errSecSuccess {
            #if DEBUG
            print("KeychainService: Failed to save \(key.rawValue), status: \(status)")
            #endif
            return false
        }

        return true
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                #if DEBUG
                print("KeychainService: Failed to get \(key.rawValue), status: \(status)")
                #endif
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the keychain
    /// - Returns: true if delete succeeded or item didn't exist, false on error
    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success or item not found are both acceptable
        if status != errSecSuccess && status != errSecItemNotFound {
            #if DEBUG
            print("KeychainService: Failed to delete \(key.rawValue), status: \(status)")
            #endif
            return false
        }

        return true
    }
}
