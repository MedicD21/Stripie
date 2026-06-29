import Foundation
import Security

/// Minimal Keychain wrapper for storing a single string secret (the admin
/// session token). Values persist across launches and reinstalls-respecting
/// `kSecAttrAccessibleAfterFirstUnlock`, so the user stays signed in.
struct KeychainStore: Sendable {
    let service: String
    let account: String

    init(service: String = "com.stripie.auth", account: String = "session-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
