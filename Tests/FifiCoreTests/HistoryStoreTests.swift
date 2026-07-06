import Foundation
import XCTest
@testable import FifiCore

final class HistoryStoreTests: FifiCoreTestCase {
    func testSaveFetchRoundTripsAllFields() throws {
        let (_, store) = try makeStore()
        let item = makeItem(
            hash: "roundtrip-hash",
            type: .file,
            preview: "Quarterly report.pdf",
            contentText: "full searchable text",
            searchText: "Quarterly report.pdf /Users/me/Quarterly report.pdf Numbers",
            sourceAppName: "Numbers",
            sourceAppBundleID: "com.apple.iWork.Numbers",
            byteSize: 42,
            blobPath: "blobs/roundtrip-hash.txt",
            thumbnailPath: "thumbnails/roundtrip-hash.png",
            fileReference: "/Users/me/Quarterly report.pdf",
            metadataJSON: "{\"count\":1}"
        )

        let saved = try store.save(item)
        let fetched = try XCTUnwrap(store.item(id: saved.id))

        XCTAssertGreaterThan(saved.id, 0)
        XCTAssertEqual(fetched.id, saved.id)
        XCTAssertEqual(fetched.contentHash, "roundtrip-hash")
        XCTAssertEqual(fetched.type, .file)
        XCTAssertEqual(fetched.previewText, "Quarterly report.pdf")
        XCTAssertEqual(fetched.contentText, "full searchable text")
        XCTAssertEqual(fetched.sourceAppName, "Numbers")
        XCTAssertEqual(fetched.sourceAppBundleID, "com.apple.iWork.Numbers")
        XCTAssertEqual(fetched.useCount, 0)
        XCTAssertFalse(fetched.isPinned)
        XCTAssertEqual(fetched.byteSize, 42)
        XCTAssertEqual(fetched.blobPath, "blobs/roundtrip-hash.txt")
        XCTAssertEqual(fetched.thumbnailPath, "thumbnails/roundtrip-hash.png")
        XCTAssertEqual(fetched.fileReference, "/Users/me/Quarterly report.pdf")
        XCTAssertEqual(fetched.metadataJSON, "{\"count\":1}")
        XCTAssertNil(fetched.lastUsedAt)
        XCTAssertLessThan(abs(fetched.createdAt.timeIntervalSinceNow), 5)
        XCTAssertLessThan(abs(fetched.updatedAt.timeIntervalSinceNow), 5)
    }

    func testDedupeBumpsUpdatedAtUseCountRefreshesSourceAndMovesToTop() throws {
        let (_, store) = try makeStore()
        let first = try store.save(makeItem(hash: "same", preview: "First", sourceAppName: "Old App"))
        waitForDistinctTimestamp()
        let other = try store.save(makeItem(hash: "other", preview: "Other"))
        XCTAssertEqual(try store.recentItems(limit: 1, offset: 0).first?.id, other.id)

        waitForDistinctTimestamp()
        let deduped = try store.save(makeItem(hash: "same", preview: "Changed preview", sourceAppName: "New App", sourceAppBundleID: "com.example.new"))
        let fetched = try XCTUnwrap(store.item(id: first.id))

        XCTAssertEqual(deduped.id, first.id)
        XCTAssertEqual(try store.itemCount(), 2)
        XCTAssertGreaterThan(fetched.updatedAt, first.updatedAt)
        XCTAssertEqual(fetched.useCount, first.useCount + 1)
        XCTAssertEqual(fetched.sourceAppName, "New App")
        XCTAssertEqual(fetched.sourceAppBundleID, "com.example.new")
        XCTAssertEqual(try store.recentItems(limit: 1, offset: 0).first?.id, first.id)
    }

    func testRecentItemsPaginatesPinnedFirstThenUpdatedDescending() throws {
        let (_, store) = try makeStore()
        let oldest = try store.save(makeItem(hash: "oldest", preview: "Oldest"))
        waitForDistinctTimestamp()
        let middle = try store.save(makeItem(hash: "middle", preview: "Middle"))
        waitForDistinctTimestamp()
        let newest = try store.save(makeItem(hash: "newest", preview: "Newest"))
        try store.setPinned(id: oldest.id, true)

        let firstPage = try store.recentItems(limit: 2, offset: 0)
        let secondPage = try store.recentItems(limit: 2, offset: 2)

        XCTAssertEqual(firstPage.map(\.id), [oldest.id, newest.id])
        XCTAssertEqual(secondPage.map(\.id), [middle.id])
    }

    func testMarkUsedMovesItemToTopAndIncrementsUsage() throws {
        let (_, store) = try makeStore()
        let first = try store.save(makeItem(hash: "first", preview: "First"))
        waitForDistinctTimestamp()
        let second = try store.save(makeItem(hash: "second", preview: "Second"))
        XCTAssertEqual(try store.recentItems(limit: 1, offset: 0).first?.id, second.id)

        waitForDistinctTimestamp()
        try store.markUsed(id: first.id)
        let used = try XCTUnwrap(store.item(id: first.id))

        XCTAssertEqual(used.useCount, first.useCount + 1)
        XCTAssertNotNil(used.lastUsedAt)
        XCTAssertGreaterThan(used.updatedAt, first.updatedAt)
        XCTAssertEqual(try store.recentItems(limit: 1, offset: 0).first?.id, first.id)
    }

    func testSetPinnedRaisesAboveNewerUnpinnedAndCanUnset() throws {
        let (_, store) = try makeStore()
        let first = try store.save(makeItem(hash: "first", preview: "First"))
        waitForDistinctTimestamp()
        let second = try store.save(makeItem(hash: "second", preview: "Second"))

        try store.setPinned(id: first.id, true)
        XCTAssertTrue(try XCTUnwrap(store.item(id: first.id)).isPinned)
        XCTAssertEqual(try store.recentItems(limit: 2, offset: 0).map(\.id), [first.id, second.id])

        try store.setPinned(id: first.id, false)
        XCTAssertFalse(try XCTUnwrap(store.item(id: first.id)).isPinned)
        XCTAssertEqual(try store.recentItems(limit: 2, offset: 0).map(\.id), [second.id, first.id])
    }

    func testDeleteReturnsRowRemovesItemAndFTSEntry() throws {
        let (_, store) = try makeStore()
        let saved = try store.save(makeItem(hash: "delete-me", preview: "Delete", searchText: "unique-delete-needle"))
        XCTAssertEqual(try store.search("unique-delete", limit: 10, offset: 0).map(\.id), [saved.id])

        let deleted = try XCTUnwrap(store.delete(id: saved.id))

        XCTAssertEqual(deleted.id, saved.id)
        XCTAssertNil(try store.item(id: saved.id))
        XCTAssertTrue(try store.search("unique-delete", limit: 10, offset: 0).isEmpty)
        XCTAssertNil(try store.delete(id: saved.id))
    }

    func testClearAllKeepPinnedPreservesPinnedAndReturnsRemovedRows() throws {
        let (_, store) = try makeStore()
        let pinned = try store.save(makeItem(hash: "pinned", preview: "Pinned", byteSize: 5))
        let unpinnedA = try store.save(makeItem(hash: "unpinned-a", preview: "A", byteSize: 7))
        let unpinnedB = try store.save(makeItem(hash: "unpinned-b", preview: "B", byteSize: 11))
        try store.setPinned(id: pinned.id, true)

        let removed = try store.clearAll(keepPinned: true)

        XCTAssertEqual(Set(removed.map(\.id)), Set([unpinnedA.id, unpinnedB.id]))
        XCTAssertEqual(try store.itemCount(), 1)
        XCTAssertEqual(try store.totalBytes(), 5)
        XCTAssertEqual(try store.recentItems(limit: 10, offset: 0).map(\.id), [pinned.id])
    }

    func testClearTypeOnlyRemovesThatTypeAndTotalsReflectRemainingRows() throws {
        let (_, store) = try makeStore()
        let text = try store.save(makeItem(hash: "text", type: .text, preview: "Text", byteSize: 3))
        let urlA = try store.save(makeItem(hash: "url-a", type: .url, preview: "https://a.example", byteSize: 5))
        let urlB = try store.save(makeItem(hash: "url-b", type: .url, preview: "https://b.example", byteSize: 7))

        let removed = try store.clear(type: .url)

        XCTAssertEqual(Set(removed.map(\.id)), Set([urlA.id, urlB.id]))
        XCTAssertEqual(try store.itemCount(), 1)
        XCTAssertEqual(try store.totalBytes(), 3)
        XCTAssertEqual(try store.recentItems(limit: 10, offset: 0).map(\.id), [text.id])
        XCTAssertTrue(try store.search("https", limit: 10, offset: 0).isEmpty)
    }
}
