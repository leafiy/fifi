import Foundation

public enum AppPrivacyMode: String, CaseIterable, Sendable, Codable {
    /// Every capture from the app is treated as sensitive content.
    case sensitive
    /// Captures from the app are kept in memory only, never written to disk.
    case memoryOnly = "memory_only"
}

public struct AppPrivacyRule: Sendable, Equatable, Identifiable, Codable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String?
    public var mode: AppPrivacyMode

    public init(bundleID: String, appName: String? = nil, mode: AppPrivacyMode) {
        self.bundleID = bundleID
        self.appName = appName
        self.mode = mode
    }
}

public final class AppPrivacyStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
        try? SchemaMigrator.migrate(database)
    }

    public func rules() throws -> [AppPrivacyRule] {
        try database.query(
            "SELECT bundle_id, app_name, mode FROM app_privacy_rules ORDER BY app_name COLLATE NOCASE, bundle_id COLLATE NOCASE",
            []
        ).compactMap(Self.rule)
    }

    public func setRule(bundleID: String, appName: String?, mode: AppPrivacyMode) throws {
        try database.run(
            """
            INSERT INTO app_privacy_rules (bundle_id, app_name, mode) VALUES (?, ?, ?)
            ON CONFLICT(bundle_id) DO UPDATE SET app_name = excluded.app_name, mode = excluded.mode
            """,
            [.text(bundleID), appName.map(SQLValue.text) ?? .null, .text(mode.rawValue)]
        )
    }

    public func removeRule(bundleID: String) throws {
        try database.run("DELETE FROM app_privacy_rules WHERE bundle_id = ?", [.text(bundleID)])
    }

    private static func rule(from row: [String: SQLValue]) -> AppPrivacyRule? {
        guard case let .text(bundleID)? = row["bundle_id"],
              case let .text(rawMode)? = row["mode"],
              let mode = AppPrivacyMode(rawValue: rawMode) else { return nil }
        var appName: String?
        if case let .text(name)? = row["app_name"] { appName = name }
        return AppPrivacyRule(bundleID: bundleID, appName: appName, mode: mode)
    }
}
