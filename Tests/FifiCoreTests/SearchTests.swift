import Foundation
import XCTest
@testable import FifiCore

final class SearchTests: FifiCoreTestCase {
    func testSearchIsCaseInsensitiveAndSupportsPrefixMatches() throws {
        let (_, store) = try makeStore()
        let item = try store.save(makeItem(hash: "hello", preview: "Hello world", searchText: "Hello world"))

        XCTAssertEqual(try store.search("hello", limit: 10, offset: 0).map(\.id), [item.id])
        XCTAssertEqual(try store.search("HEL", limit: 10, offset: 0).map(\.id), [item.id])
    }

    func testSearchUsesMultiTokenAndSemantics() throws {
        let (_, store) = try makeStore()
        let matching = try store.save(makeItem(hash: "matching", preview: "Hello Swift", searchText: "hello swift world"))
        _ = try store.save(makeItem(hash: "missing", preview: "Hello Other", searchText: "hello other world"))

        XCTAssertEqual(try store.search("hello swift", limit: 10, offset: 0).map(\.id), [matching.id])
    }

    func testSearchIndexesURLFilePathFileNameAndSourceAppViaSearchText() throws {
        let (_, store) = try makeStore()
        let url = try store.save(makeItem(hash: "url", type: .url, preview: "https://example.com/path", searchText: "https://example.com/path Example Browser"))
        let file = try store.save(makeItem(hash: "file", type: .file, preview: "Budget.xlsx", searchText: "/Users/me/Documents/Budget.xlsx Budget.xlsx Finder"))
        let app = try store.save(makeItem(hash: "app", preview: "Plain text", searchText: "Plain text Notes", sourceAppName: "Notes"))

        XCTAssertEqual(try store.search("example", limit: 10, offset: 0).map(\.id), [url.id])
        XCTAssertEqual(try store.search("Documents", limit: 10, offset: 0).map(\.id), [file.id])
        XCTAssertEqual(try store.search("Budget", limit: 10, offset: 0).map(\.id), [file.id])
        XCTAssertEqual(try store.search("Notes", limit: 10, offset: 0).map(\.id), [app.id])
    }

    func testEmptyOrWhitespaceQueryReturnsRecentsWithPagination() throws {
        let (_, store) = try makeStore()
        let first = try store.save(makeItem(hash: "first", preview: "First"))
        waitForDistinctTimestamp()
        let second = try store.save(makeItem(hash: "second", preview: "Second"))
        waitForDistinctTimestamp()
        let third = try store.save(makeItem(hash: "third", preview: "Third"))

        XCTAssertEqual(try store.search("", limit: 2, offset: 0).map(\.id), [third.id, second.id])
        XCTAssertEqual(try store.search("   \n\t  ", limit: 2, offset: 1).map(\.id), [second.id, first.id])
    }

    func testFTSOperatorInjectionDoesNotThrow() throws {
        let (_, store) = try makeStore()
        _ = try store.save(makeItem(hash: "safe", preview: "Foo bar", searchText: "foo bar baz"))

        XCTAssertNoThrow(try store.search("\"foo\" OR bar(", limit: 10, offset: 0))
    }

    func testSearchRespectsLimitAndOffset() throws {
        let (_, store) = try makeStore()
        let oldest = try store.save(makeItem(hash: "oldest", preview: "Common oldest", searchText: "common oldest"))
        waitForDistinctTimestamp()
        let middle = try store.save(makeItem(hash: "middle", preview: "Common middle", searchText: "common middle"))
        waitForDistinctTimestamp()
        let newest = try store.save(makeItem(hash: "newest", preview: "Common newest", searchText: "common newest"))

        XCTAssertEqual(try store.search("common", limit: 1, offset: 0).map(\.id), [newest.id])
        XCTAssertEqual(try store.search("common", limit: 1, offset: 1).map(\.id), [middle.id])
        XCTAssertEqual(try store.search("common", limit: 1, offset: 2).map(\.id), [oldest.id])
    }
}
