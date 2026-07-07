import FifiCore
import Foundation
import Security

/// Fetches or creates the 32-byte AES key used for at-rest blob encryption,
/// stored in the login Keychain. Never logs or exports the key material.
enum EncryptionKeyStore {
    private static let service = "com.leafiy.fifi.encryption"
    private static let account = "blob-key"

    enum KeyStoreError: Error {
        case randomGenerationFailed(OSStatus)
        case keychainWriteFailed(OSStatus)
        case keychainReadFailed(OSStatus)
    }

    /// Returns the existing key, generating and persisting one on first use.
    static func keyData() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeyStoreError.randomGenerationFailed(status)
        }
        let key = Data(bytes)
        try storeKey(key)
        return key
    }

    static func makeCipher() throws -> BlobCipher {
        try AESGCMBlobCipher(keyData: keyData())
    }

    /// Removes the key. Existing encrypted blobs become unreadable, so callers
    /// must only do this when encryption is being disabled and blobs re-written.
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychainReadFailed(status)
        }
    }

    private static func storeKey(_ key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeyStoreError.keychainWriteFailed(status)
        }
    }
}
