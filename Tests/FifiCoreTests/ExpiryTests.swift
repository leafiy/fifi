import Foundation
import XCTest
@testable import FifiCore

final class ExpiryTests: FifiCoreTestCase {
    func testDeleteExpiredRemovesPastDeadlinesIncludingPinnedAndKeepsFutureRows() throws {
        let (_, store) = try makeStore()
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let expired = try store.save(expiringItem(hash: "expired", preview: "Expired", expiresAt: reference.addingTimeInterval(-1)))
        let pinnedExpired = try store.save(expiringItem(hash: "pinned-expired", preview: "Pinned expired", expiresAt: reference.addingTimeInterval(-60)))
        let future = try store.save(expiringItem(hash: "future", preview: "Future", expiresAt: reference.addingTimeInterval(60)))
        try store.setPinned(id: pinnedExpired.id, true)

        let removed = try store.deleteExpired(reference: reference)

        XCTAssertEqual(Set(removed.map(\.id)), Set([expired.id, pinnedExpired.id]))
        XCTAssertNil(try store.item(id: expired.id))
        XCTAssertNil(try store.item(id: pinnedExpired.id))
        XCTAssertEqual(try store.item(id: future.id)?.id, future.id)
    }

    func testCleanupPolicyAlwaysDropsPastExpiryRows() throws {
        let (_, store) = try makeStore()
        let expired = try store.save(expiringItem(hash: "expired", preview: "Expired", expiresAt: Date().addingTimeInterval(-60)))
        let survivor = try store.save(expiringItem(hash: "survivor", preview: "Survivor", expiresAt: Date().addingTimeInterval(3_600)))

        let removed = try store.cleanup(policy: CleanupPolicy())

        XCTAssertEqual(removed.map(\.id), [expired.id])
        XCTAssertNil(try store.item(id: expired.id))
        XCTAssertEqual(try store.item(id: survivor.id)?.id, survivor.id)
    }

    private func expiringItem(hash: String, preview: String, expiresAt: Date) -> NewClipboardItem {
        NewClipboardItem(
            contentHash: hash,
            type: .text,
            previewText: preview,
            contentText: preview,
            searchText: preview,
            isSensitive: true,
            expiresAt: expiresAt,
            byteSize: Data(preview.utf8).count
        )
    }
}
