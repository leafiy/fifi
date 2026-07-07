#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// AES-256-GCM blob encryption. The 32-byte key lives in the login Keychain
/// (see the app target's EncryptionKeyStore); FifiCore only consumes key data.
/// CryptoKit is Apple-platform only, so this type is unavailable in the Linux
/// core build — `BlobCipher` keeps the rest of the core platform-neutral.
public struct AESGCMBlobCipher: BlobCipher {
    public enum CipherError: Error {
        case invalidKeyLength(Int)
        case malformedPayload
    }

    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == 32 else {
            throw CipherError.invalidKeyLength(keyData.count)
        }
        self.key = SymmetricKey(data: keyData)
    }

    public func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else {
            // combined is only nil for custom-size nonces; the default 12-byte
            // nonce always yields a combined representation.
            throw CipherError.malformedPayload
        }
        return combined
    }

    public func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}
#endif
