import Dispatch
import Foundation
import XCTest
@testable import FifiCore

final class ConcurrencyTests: FifiCoreTestCase {
    func testHistoryStoreSerializesConcurrentSaveReadAndCleanupOnSingleConnection() throws {
        let (_, store) = try makeStore()
        let iterations = 8
        let savesPerIteration = 20
        let cleanupPolicy = CleanupPolicy(maxCount: 50)
        let sharedHash = "shared-concurrency-hash"
        let sharedItem = makeItem(
            hash: sharedHash,
            preview: "Shared concurrency item",
            searchText: "sharedneedle concurrency shared"
        )
        let distinctItems = (0..<iterations).map { iteration in
            (0..<savesPerIteration).map { itemIndex in
                makeItem(
                    hash: "concurrent-\(iteration)-\(itemIndex)",
                    preview: "Concurrent item \(iteration)-\(itemIndex)",
                    searchText: "concurrency unique \(iteration) \(itemIndex)"
                )
            }
        }
        let errors = LockedErrors()

        DispatchQueue.concurrentPerform(iterations: iterations) { iteration in
            do {
                for itemIndex in 0..<savesPerIteration {
                    try store.save(distinctItems[iteration][itemIndex])

                    if itemIndex % 5 == 0 {
                        try store.save(sharedItem)
                    }

                    if itemIndex % 7 == 0 {
                        _ = try store.search("concurrency", limit: 5, offset: 0)
                        _ = try store.recentItems(limit: 5, offset: 0)
                    }

                    if itemIndex == 9 {
                        _ = try store.cleanup(policy: cleanupPolicy)
                    }
                }

                _ = try store.search("sharedneedle", limit: 5, offset: 0)
                _ = try store.recentItems(limit: 10, offset: 0)
                _ = try store.cleanup(policy: cleanupPolicy)
                try store.save(sharedItem)
            } catch {
                errors.record(error, iteration: iteration)
            }
        }

        let failures = errors.snapshot()
        if !failures.isEmpty {
            XCTFail("Concurrent HistoryStore operations threw errors:\n\(failures.joined(separator: "\n"))")
            return
        }

        waitForDistinctTimestamp()
        try store.save(sharedItem)
        _ = try store.cleanup(policy: cleanupPolicy)

        let itemCount = try store.itemCount()
        XCTAssertGreaterThan(itemCount, 0)
        XCTAssertLessThanOrEqual(itemCount, 50)

        let recentItems = try store.recentItems(limit: 100, offset: 0)
        XCTAssertEqual(recentItems.count, itemCount)
        XCTAssertEqual(Set(recentItems.map(\.contentHash)).count, recentItems.count)

        let sharedMatches = try store.search("sharedneedle", limit: 10, offset: 0)
            .filter { $0.contentHash == sharedHash }
        XCTAssertEqual(sharedMatches.count, 1)
    }

    private final class LockedErrors {
        private let lock = NSLock()
        private var messages: [String] = []

        func record(_ error: Error, iteration: Int) {
            lock.lock()
            messages.append("iteration \(iteration): \(error)")
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            let snapshot = messages
            lock.unlock()
            return snapshot
        }
    }
}
