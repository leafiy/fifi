import Foundation
import XCTest
@testable import FifiCore

class FifiCoreTestCase: XCTestCase {
    private var tempDirectories: [URL] = []
    private var databases: [Database] = []

    override func tearDownWithError() throws {
        for database in databases {
            database.close()
        }
        databases.removeAll()

        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()

        try super.tearDownWithError()
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FifiCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectories.append(directory)
        return directory
    }

    func makeStore() throws -> (Database, HistoryStore) {
        let directory = try makeTemporaryDirectory()
        let database = try Database(path: directory.appendingPathComponent("fifi.sqlite3").path)
        databases.append(database)
        let store = try HistoryStore(database: database)
        return (database, store)
    }

    func makeBlobStore() throws -> BlobStore {
        try BlobStore(rootDirectory: makeTemporaryDirectory())
    }

    func makeItem(
        hash: String = UUID().uuidString,
        type: ClipItemType = .text,
        preview: String = "Preview text",
        contentText: String? = nil,
        searchText: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        byteSize: Int? = nil,
        blobPath: String? = nil,
        thumbnailPath: String? = nil,
        fileReference: String? = nil,
        metadataJSON: String? = nil
    ) -> NewClipboardItem {
        let inlineText = contentText ?? preview
        return NewClipboardItem(
            contentHash: hash,
            type: type,
            previewText: preview,
            contentText: contentText,
            searchText: searchText ?? inlineText,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            byteSize: byteSize ?? Data(inlineText.utf8).count,
            blobPath: blobPath,
            thumbnailPath: thumbnailPath,
            fileReference: fileReference,
            metadataJSON: metadataJSON
        )
    }

    func waitForDistinctTimestamp() {
        Thread.sleep(forTimeInterval: 0.02)
    }
}
