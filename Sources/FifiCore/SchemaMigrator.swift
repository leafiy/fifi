import Foundation

/// Versioned schema management on top of `PRAGMA user_version`.
///
/// Version 0 is ambiguous: it is both a brand-new database and a pre-migrator
/// V1 install (V1 created its schema with bare `CREATE TABLE IF NOT EXISTS`).
/// The migrator disambiguates by probing for the baseline table before
/// deciding whether to create the baseline or merely stamp it.
public enum SchemaMigrator {
    public static let currentVersion = 2

    /// Idempotent and cheap when the database is already current.
    public static func migrate(_ database: Database) throws {
        guard try userVersion(database) < currentVersion else { return }
        try database.transaction {
            var version = try userVersion(database)
            if version == 0 {
                if try !hasBaselineTables(database) {
                    try createBaseline(database)
                }
                version = 1
            }
            if version < 2 {
                try migrateToV2(database)
                version = 2
            }
            try database.execute("PRAGMA user_version = \(version)")
        }
    }

    public static func userVersion(_ database: Database) throws -> Int {
        let rows = try database.query("PRAGMA user_version", [])
        if case let .integer(value)? = rows.first?["user_version"] {
            return Int(value)
        }
        return 0
    }

    // MARK: - Baseline (V1)

    private static func hasBaselineTables(_ database: Database) throws -> Bool {
        let rows = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items' LIMIT 1",
            []
        )
        return !rows.isEmpty
    }

    private static func createBaseline(_ database: Database) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clipboard_items (
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
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_order ON clipboard_items(is_pinned DESC, updated_at DESC);"
        )
        try database.execute("CREATE INDEX IF NOT EXISTS idx_items_type ON clipboard_items(type);")
        try database.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(content, tokenize='unicode61');"
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS ignore_apps (
              bundle_id TEXT PRIMARY KEY, app_name TEXT
            );
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS ignore_regex_rules (
              id INTEGER PRIMARY KEY AUTOINCREMENT, pattern TEXT NOT NULL, label TEXT, enabled INTEGER NOT NULL DEFAULT 1
            );
            """
        )
    }

    // MARK: - V2: privacy columns and per-app privacy rules

    private static func migrateToV2(_ database: Database) throws {
        if try !columnExists(database, table: "clipboard_items", column: "is_sensitive") {
            try database.execute(
                "ALTER TABLE clipboard_items ADD COLUMN is_sensitive INTEGER NOT NULL DEFAULT 0;"
            )
        }
        if try !columnExists(database, table: "clipboard_items", column: "expires_at") {
            try database.execute("ALTER TABLE clipboard_items ADD COLUMN expires_at REAL;")
        }
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_items_expires
            ON clipboard_items(expires_at) WHERE expires_at IS NOT NULL;
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS app_privacy_rules (
              bundle_id TEXT PRIMARY KEY, app_name TEXT, mode TEXT NOT NULL
            );
            """
        )
    }

    private static func columnExists(_ database: Database, table: String, column: String) throws -> Bool {
        try database.query("PRAGMA table_info(\(table))", []).contains { row in
            if case let .text(name)? = row["name"] { return name == column }
            return false
        }
    }
}
