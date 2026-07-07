import Foundation
import XCTest
@testable import FifiCore

private struct ReversingCipher: BlobCipher {
    func seal(_ data: Data) throws -> Data {
        Data(data.reversed())
    }

    func open(_ data: Data) throws -> Data {
        Data(data.reversed())
    }
}

final class BlobEncryptionTests: FifiCoreTestCase {
    func testCipherWritesMagicPrefixedEncryptedBlobAndReadsOriginalData() throws {
        let store = try makeBlobStore()
        let original = Data("secret blob".utf8)
        store.setCipher(ReversingCipher())

        let path = try store.storeBlob(original, hash: "encrypted", fileExtension: "txt")
        let raw = try Data(contentsOf: store.url(forRelativePath: path))

        XCTAssertTrue(store.hasCipher)
        XCTAssertTrue(raw.starts(with: Data("fifi-enc1".utf8)))
        XCTAssertNotEqual(raw, original)
        XCTAssertEqual(try store.data(atRelativePath: path), original)
    }

    func testPlaintextBlobWrittenBeforeCipherStaysReadableAfterCipherEnabled() throws {
        let store = try makeBlobStore()
        let original = Data("legacy plaintext".utf8)
        let path = try store.storeBlob(original, hash: "legacy", fileExtension: "txt")
        let rawBeforeCipher = try Data(contentsOf: store.url(forRelativePath: path))
        XCTAssertEqual(rawBeforeCipher, original)

        store.setCipher(ReversingCipher())

        XCTAssertEqual(try store.data(atRelativePath: path), original)
    }

    #if canImport(CryptoKit)
    func testAESGCMBlobCipherSealsAndOpensPayload() throws {
        let cipher = try AESGCMBlobCipher(keyData: Data(repeating: 7, count: 32))
        let original = Data("authenticated secret".utf8)

        let sealed = try cipher.seal(original)

        XCTAssertNotEqual(sealed, original)
        XCTAssertEqual(try cipher.open(sealed), original)
    }
    #endif
}
