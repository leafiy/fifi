import Foundation
import XCTest
@testable import FifiCore

final class CleanupTests: FifiCoreTestCase {
    func testMaxCountEvictsOldestNonPinnedKeepingNewestRows() throws {
        let (_, store) = try makeStore()
        let pinned = try store.save(makeItem(hash: "pinned-old", preview: "Pinned old"))
        try store.setPinned(id: pinned.id, true)
        waitForDistinctTimestamp()
        let old = try store.save(makeItem(hash: "old", preview: "Old"))
        waitForDistinctTimestamp()
        let middle = try store.save(makeItem(hash: "middle", preview: "Middle"))
        waitForDistinctTimestamp()
        let newest = try store.save(makeItem(hash: "newest", preview: "Newest"))

        let removed = try store.cleanup(policy: CleanupPolicy(maxCount: 2))

        XCTAssertEqual(removed.map(\.id), [old.id])
        XCTAssertNotNil(try store.item(id: pinned.id))
        XCTAssertEqual(Set(try store.recentItems(limit: 10, offset: 0).map(\.id)), Set([pinned.id, middle.id, newest.id]))
    }

    func testMaxAgeDaysEvictsOldNonPinnedRowsAndReturnsBlobPaths() throws {
        let (database, store) = try makeStore()
        let old = try store.save(makeItem(hash: "old", preview: "Old", byteSize: 10, blobPath: "blobs/old.txt"))
        let fresh = try store.save(makeItem(hash: "fresh", preview: "Fresh", byteSize: 10, blobPath: "blobs/fresh.txt"))
        try backdate(itemID: old.id, days: 3, database: database)

        let removed = try store.cleanup(policy: CleanupPolicy(maxAgeDays: 1))

        XCTAssertEqual(removed.map(\.id), [old.id])
        XCTAssertEqual(removed.first?.blobPath, "blobs/old.txt")
        XCTAssertNil(try store.item(id: old.id))
        XCTAssertNotNil(try store.item(id: fresh.id))
    }

    func testMaxTotalBytesEvictsOldestUntilUnderBudget() throws {
        let (_, store) = try makeStore()
        let old = try store.save(makeItem(hash: "old", preview: "Old", byteSize: 60))
        waitForDistinctTimestamp()
        let middle = try store.save(makeItem(hash: "middle", preview: "Middle", byteSize: 60))
        waitForDistinctTimestamp()
        let newest = try store.save(makeItem(hash: "newest", preview: "Newest", byteSize: 60))

        let removed = try store.cleanup(policy: CleanupPolicy(maxTotalBytes: 100))

        XCTAssertEqual(removed.map(\.id), [old.id, middle.id])
        XCTAssertEqual(try store.totalBytes(), 60)
        XCTAssertEqual(try store.recentItems(limit: 10, offset: 0).map(\.id), [newest.id])
    }

    func testPinnedRowsAreNeverEvictedByAgeOrStoragePolicies() throws {
        let (database, store) = try makeStore()
        let pinned = try store.save(makeItem(hash: "pinned", preview: "Pinned", byteSize: 1_000, blobPath: "blobs/pinned.bin"))
        let unpinned = try store.save(makeItem(hash: "unpinned", preview: "Unpinned", byteSize: 20, blobPath: "blobs/unpinned.bin"))
        try store.setPinned(id: pinned.id, true)
        try backdate(itemID: pinned.id, days: 90, database: database)
        try backdate(itemID: unpinned.id, days: 90, database: database)

        let removed = try store.cleanup(policy: CleanupPolicy(maxAgeDays: 1, maxTotalBytes: 1))

        XCTAssertFalse(removed.map(\.id).contains(pinned.id))
        XCTAssertTrue(removed.map(\.id).contains(unpinned.id))
        XCTAssertNotNil(try store.item(id: pinned.id))
        XCTAssertEqual(try store.recentItems(limit: 10, offset: 0).map(\.id), [pinned.id])
    }

    func testNilCleanupPolicyFieldsAreNoOp() throws {
        let (_, store) = try makeStore()
        let first = try store.save(makeItem(hash: "first", preview: "First", byteSize: 10))
        let second = try store.save(makeItem(hash: "second", preview: "Second", byteSize: 20))

        let removed = try store.cleanup(policy: CleanupPolicy())

        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(try store.itemCount(), 2)
        XCTAssertEqual(try store.totalBytes(), 30)
        XCTAssertEqual(Set(try store.recentItems(limit: 10, offset: 0).map(\.id)), Set([first.id, second.id]))
    }

    private func backdate(itemID: Int64, days: Int, database: Database) throws {
        let timestamp = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60).timeIntervalSince1970
        try database.run(
            "UPDATE clipboard_items SET updated_at = ? WHERE id = ?",
            [.real(timestamp), .integer(itemID)]
        )
    }
}
