import Foundation
import Security

/// Abstraction over Keychain operations for deterministic unit testing.
protocol KeychainStoring: Sendable {
    func readString(account: String) -> String?
    func writeString(_ value: String, account: String) -> Bool
    func deleteValue(account: String) -> Bool
}

/// Provides the app's anonymous user identifier (invariant #1 in AGENTS.md).
protocol AnonymousUserIDProviding: Sendable {
    func getOrCreateAnonymousUserUUID() -> String
}

/// Production Security.framework Keychain store using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
struct SecurityKeychainStore: KeychainStoring {
    let service: String

    init(service: String = AppConfig.keychainService) {
        self.service = service
    }

    func readString(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func writeString(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        if addStatus == errSecDuplicateItem {
            let matchQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ]
            let updateAttributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            return SecItemUpdate(matchQuery as CFDictionary, updateAttributes as CFDictionary) == errSecSuccess
        }
        return false
    }

    func deleteValue(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Thread-safe helper that creates and persists a single lowercase UUID v4 per device installation.
final class KeychainHelper: AnonymousUserIDProviding, @unchecked Sendable {
    private let store: any KeychainStoring
    private let account: String
    private let lock = NSLock()

    init(
        store: any KeychainStoring = SecurityKeychainStore(),
        account: String = AppConfig.keychainAnonymousUserUUIDAccount
    ) {
        self.store = store
        self.account = account
    }

    func getOrCreateAnonymousUserUUID() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = store.readString(account: account),
           let parsed = UUID(uuidString: existing) {
            return parsed.uuidString.lowercased()
        }

        let newUUID = UUID().uuidString.lowercased()
        _ = store.writeString(newUUID, account: account)
        return newUUID
    }
}
