import Foundation
import XCTest
@testable import FifiCore

final class BlobStoreTests: FifiCoreTestCase {
    func testStoreBlobAndDataRoundTrip() throws {
        let store = try makeBlobStore()
        let data = Data([0, 1, 2, 3, 4])

        let path = try store.storeBlob(data, hash: "abc123", fileExtension: "bin")

        XCTAssertEqual(path, "blobs/abc123.bin")
        XCTAssertEqual(try store.data(atRelativePath: path), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(forRelativePath: path).path))
    }

    func testStoreBlobIsIdempotentForSameHashAndExtension() throws {
        let store = try makeBlobStore()
        let first = Data("first".utf8)
        let second = Data("second".utf8)

        let firstPath = try store.storeBlob(first, hash: "same", fileExtension: "txt")
        let secondPath = try store.storeBlob(second, hash: "same", fileExtension: "txt")

        XCTAssertEqual(secondPath, firstPath)
        XCTAssertEqual(try store.data(atRelativePath: firstPath), first)
    }

    func testDeleteIsBestEffortAndRemovesExistingFile() throws {
        let store = try makeBlobStore()
        let path = try store.storeBlob(Data("delete me".utf8), hash: "delete", fileExtension: "txt")

        XCTAssertNoThrow(store.delete(relativePath: "blobs/does-not-exist.txt"))
        store.delete(relativePath: path)

        XCTAssertThrowsError(try store.data(atRelativePath: path))
    }

    func testTotalBytesSumsStoredBlobsAndThumbnails() throws {
        let store = try makeBlobStore()
        _ = try store.storeBlob(Data([1, 2, 3]), hash: "blob", fileExtension: "bin")
        _ = try store.storeThumbnail(Data([4, 5, 6, 7]), hash: "thumb")

        XCTAssertEqual(store.totalBytes(), 7)
    }

    func testDeleteAllEmptiesStoreButLeavesDirectoriesUsable() throws {
        let store = try makeBlobStore()
        _ = try store.storeBlob(Data([1, 2, 3]), hash: "blob", fileExtension: "bin")
        _ = try store.storeThumbnail(Data([4, 5]), hash: "thumb")
        XCTAssertGreaterThan(store.totalBytes(), 0)

        store.deleteAll()

        XCTAssertEqual(store.totalBytes(), 0)
        let path = try store.storeBlob(Data("after".utf8), hash: "after", fileExtension: "txt")
        XCTAssertEqual(try store.data(atRelativePath: path), Data("after".utf8))
    }
}
