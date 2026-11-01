import Foundation
import Security

enum Keychain {
    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "app.habitaker.authproof",
                                   kSecAttrAccount as String: account,
                                   kSecReturnData as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthFailure.invalid("Secure storage is unavailable. Unlock your iPhone and try again.") }
        return item as? Data
    }

    static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "app.habitaker.authproof",
                                   kSecAttrAccount as String: account]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AuthFailure.invalid("Could not save sign-in securely. Try again.")
            }
        } else if status != errSecSuccess {
            throw AuthFailure.invalid("Could not update secure sign-in storage.")
        }
    }
}
