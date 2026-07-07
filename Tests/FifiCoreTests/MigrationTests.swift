import Foundation
import XCTest
@testable import FifiCore

final class MigrationTests: FifiCoreTestCase {
    func testFreshStoreMigratesToCurrentSchemaVersion() throws {
        let (database, _) = try makeStore()

        XCTAssertEqual(try SchemaMigrator.userVersion(database), SchemaMigrator.currentVersion)
        XCTAssertEqual(SchemaMigrator.currentVersion, 2)
    }

    func testV1DatabaseGainsPrivacyColumnsAndMigrationIsIdempotent() throws {
        let directory = try makeTemporaryDirectory()
        let databaseURL = directory.appendingPathComponent("v1.sqlite3")
        let database = try Database(path: databaseURL.path)
        defer { database.close() }

        try createV1Schema(in: database)
        XCTAssertEqual(try SchemaMigrator.userVersion(database), 0)

        _ = try HistoryStore(database: database)

        XCTAssertEqual(try SchemaMigrator.userVersion(database), 2)
        XCTAssertTrue(try columnNames(in: database, table: "clipboard_items").contains("is_sensitive"))
        XCTAssertTrue(try columnNames(in: database, table: "clipboard_items").contains("expires_at"))

        let columnsAfterFirstMigration = try columnNames(in: database, table: "clipboard_items")
        try SchemaMigrator.migrate(database)
        try SchemaMigrator.migrate(database)

        XCTAssertEqual(try SchemaMigrator.userVersion(database), 2)
        XCTAssertEqual(try columnNames(in: database, table: "clipboard_items"), columnsAfterFirstMigration)
    }

    private func createV1Schema(in database: Database) throws {
        try database.execute(
            """
            CREATE TABLE clipboard_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              content_hash TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              preview_text TEXT NOT NULL DEFAULT '',
              content_text TEXT,
              source_app_name TEXT,
              source_app_bundle_id TEXT,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              last_used_at REAL,
              use_count INTEGER NOT NULL DEFAULT 0,
              is_pinned INTEGER NOT NULL DEFAULT 0,
              byte_size INTEGER NOT NULL DEFAULT 0,
              blob_path TEXT,
              thumbnail_path TEXT,
              file_reference TEXT,
              metadata_json TEXT
            );
            """
        )
        try database.execute("CREATE INDEX idx_items_order ON clipboard_items(is_pinned DESC, updated_at DESC);")
        try database.execute("CREATE INDEX idx_items_type ON clipboard_items(type);")
        try database.execute("CREATE VIRTUAL TABLE clipboard_items_fts USING fts5(content, tokenize='unicode61');")
    }

    private func columnNames(in database: Database, table: String) throws -> [String] {
        try database.query("PRAGMA table_info(\(table))", []).compactMap { row in
            if case let .text(name)? = row["name"] { return name }
            return nil
        }
    }
}
