import Foundation
import XCTest
@testable import FifiCore

final class FilteredQueryTests: FifiCoreTestCase {
    func testItemsMatchingAppliesFiltersAndSortOrders() throws {
        let (database, store) = try makeStore()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let notes = try store.save(makeItem(
            hash: "notes",
            type: .text,
            preview: "Notes clipping",
            searchText: "Notes clipping",
            sourceAppName: "Notes",
            sourceAppBundleID: "com.apple.Notes"
        ))
        let safari = try store.save(makeItem(
            hash: "safari",
            type: .url,
            preview: "https://example.com",
            searchText: "https://example.com",
            sourceAppName: "Safari",
            sourceAppBundleID: "com.apple.Safari"
        ))
        let terminal = try store.save(makeItem(
            hash: "terminal",
            type: .text,
            preview: "Terminal output",
            searchText: "Terminal output",
            sourceAppName: "Terminal",
            sourceAppBundleID: "com.apple.Terminal"
        ))
        let image = try store.save(makeItem(
            hash: "image",
            type: .image,
            preview: "Screenshot",
            searchText: "Screenshot",
            sourceAppName: "Preview",
            sourceAppBundleID: "com.apple.Preview"
        ))

        try setTimestamps(for: notes.id, createdAt: baseDate.addingTimeInterval(-300), updatedAt: baseDate.addingTimeInterval(-300), database: database)
        try setTimestamps(for: safari.id, createdAt: baseDate.addingTimeInterval(-200), updatedAt: baseDate.addingTimeInterval(-200), database: database)
        try setTimestamps(for: terminal.id, createdAt: baseDate.addingTimeInterval(-100), updatedAt: baseDate.addingTimeInterval(-100), database: database)
        try setTimestamps(for: image.id, createdAt: baseDate.addingTimeInterval(-50), updatedAt: baseDate.addingTimeInterval(-50), database: database)
        try setUseCount(for: safari.id, 1, database: database)
        try setUseCount(for: terminal.id, 3, database: database)
        try setUseCount(for: image.id, 2, database: database)
        try store.setPinned(id: terminal.id, true)

        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(types: [.url])), limit: 10, offset: 0).map(\.id),
            [safari.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(sourceAppBundleIDs: ["com.apple.Notes", "com.apple.Preview"])), limit: 10, offset: 0).map(\.id),
            [image.id, notes.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(since: baseDate.addingTimeInterval(-150))), limit: 10, offset: 0).map(\.id),
            [image.id, terminal.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(until: baseDate.addingTimeInterval(-150))), limit: 10, offset: 0).map(\.id),
            [safari.id, notes.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(pinnedOnly: true)), limit: 10, offset: 0).map(\.id),
            [terminal.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(filter: HistoryFilter(minUseCount: 2)), limit: 10, offset: 0).map(\.id),
            [image.id, terminal.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(sort: .recency), limit: 10, offset: 0).map(\.id),
            [image.id, terminal.id, safari.id, notes.id]
        )
        XCTAssertEqual(
            try store.items(matching: HistoryQuery(sort: .mostUsed), limit: 10, offset: 0).map(\.id),
            [terminal.id, image.id, safari.id, notes.id]
        )
    }

    func testRegexQueryUsesRegexpAndExcludesNonMatchingRows() throws {
        let (_, store) = try makeStore()
        let matching = try store.save(makeItem(hash: "invoice-123", preview: "Invoice ABC-123", searchText: "Invoice ABC-123"))
        _ = try store.save(makeItem(hash: "invoice-abc", preview: "Invoice ABC-XYZ", searchText: "Invoice ABC-XYZ"))

        let results = try store.items(matching: HistoryQuery(text: "ABC-[0-9]{3}", isRegex: true), limit: 10, offset: 0)

        XCTAssertEqual(results.map(\.id), [matching.id])
    }

    func testFuzzyRankingReordersMatchingCandidatesBySubsequenceScore() throws {
        let (_, store) = try makeStore()
        let weaker = try store.save(makeItem(hash: "weak", preview: "Fast Config", searchText: "Fast Config"))
        waitForDistinctTimestamp()
        let stronger = try store.save(makeItem(hash: "strong", preview: "F C", searchText: "F C"))

        let ranked = try store.items(matching: HistoryQuery(text: "f c", fuzzyRanking: true), limit: 10, offset: 0)

        XCTAssertEqual(ranked.map(\.id), [stronger.id, weaker.id])
    }

    func testDistinctSourceAppsAndCountsByTypeSummarizeSavedRows() throws {
        let (_, store) = try makeStore()
        _ = try store.save(makeItem(hash: "notes-1", type: .text, preview: "A", sourceAppName: "Notes", sourceAppBundleID: "com.apple.Notes"))
        _ = try store.save(makeItem(hash: "notes-2", type: .text, preview: "B", sourceAppName: "Notes", sourceAppBundleID: "com.apple.Notes"))
        _ = try store.save(makeItem(hash: "notes-3", type: .url, preview: "C", sourceAppName: "Notes", sourceAppBundleID: "com.apple.Notes"))
        _ = try store.save(makeItem(hash: "safari-1", type: .url, preview: "D", sourceAppName: "Safari", sourceAppBundleID: "com.apple.Safari"))
        _ = try store.save(makeItem(hash: "safari-2", type: .image, preview: "E", sourceAppName: "Safari", sourceAppBundleID: "com.apple.Safari"))
        _ = try store.save(makeItem(hash: "preview-1", type: .image, preview: "F", sourceAppName: "Preview", sourceAppBundleID: "com.apple.Preview"))
        _ = try store.save(makeItem(hash: "unknown-app", type: .file, preview: "G"))

        XCTAssertEqual(
            try store.distinctSourceApps(),
            [
                SourceAppSummary(bundleID: "com.apple.Notes", appName: "Notes", itemCount: 3),
                SourceAppSummary(bundleID: "com.apple.Safari", appName: "Safari", itemCount: 2),
                SourceAppSummary(bundleID: "com.apple.Preview", appName: "Preview", itemCount: 1)
            ]
        )
        let counts = try store.countsByType()
        XCTAssertEqual(counts[.text], 2)
        XCTAssertEqual(counts[.url], 2)
        XCTAssertEqual(counts[.image], 2)
        XCTAssertEqual(counts[.file], 1)
    }

    private func setTimestamps(for id: Int64, createdAt: Date, updatedAt: Date, database: Database) throws {
        try database.run(
            "UPDATE clipboard_items SET created_at = ?, updated_at = ? WHERE id = ?",
            [.real(createdAt.timeIntervalSince1970), .real(updatedAt.timeIntervalSince1970), .integer(id)]
        )
    }

    private func setUseCount(for id: Int64, _ useCount: Int, database: Database) throws {
        try database.run("UPDATE clipboard_items SET use_count = ? WHERE id = ?", [.integer(Int64(useCount)), .integer(id)])
    }
}
