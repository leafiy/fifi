import Foundation
import XCTest
@testable import FifiCore

final class DatabaseMaintenanceTests: FifiCoreTestCase {
    func testFreshStoreIntegrityCheckIsEmpty() throws {
        let (database, _) = try makeStore()

        XCTAssertEqual(try database.integrityCheck(), [])
    }

    func testBackupCanBeOpenedAndContainsSavedRows() throws {
        let directory = try makeTemporaryDirectory()
        let (database, store) = try makeStore()
        _ = try store.save(makeItem(hash: "first", preview: "First"))
        _ = try store.save(makeItem(hash: "second", preview: "Second"))
        let backupURL = directory.appendingPathComponent("backup.sqlite3")

        try database.backup(toPath: backupURL.path)

        let backupDatabase = try Database(path: backupURL.path)
        defer { backupDatabase.close() }
        let backupStore = try HistoryStore(database: backupDatabase)
        XCTAssertEqual(try backupStore.itemCount(), 2)
    }

    func testRestoreReplacesEmptyDatabaseWithBackupRows() throws {
        let directory = try makeTemporaryDirectory()
        let (sourceDatabase, sourceStore) = try makeStore()
        let first = try sourceStore.save(makeItem(hash: "first", preview: "First"))
        let second = try sourceStore.save(makeItem(hash: "second", preview: "Second"))
        let backupURL = directory.appendingPathComponent("restore-source.sqlite3")
        try sourceDatabase.backup(toPath: backupURL.path)

        let destinationDatabase = try Database(path: directory.appendingPathComponent("destination.sqlite3").path)
        defer { destinationDatabase.close() }
        _ = try HistoryStore(database: destinationDatabase)
        XCTAssertEqual(try HistoryStore(database: destinationDatabase).itemCount(), 0)

        try destinationDatabase.restore(fromPath: backupURL.path)
        let restoredStore = try HistoryStore(database: destinationDatabase)

        XCTAssertEqual(try restoredStore.itemCount(), 2)
        XCTAssertEqual(
            Set(try restoredStore.recentItems(limit: 10, offset: 0).map(\.contentHash)),
            Set([first.contentHash, second.contentHash])
        )
    }
}
