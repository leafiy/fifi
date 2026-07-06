import Foundation

public struct IgnoreRegexRule: Sendable, Equatable, Identifiable {
    public let id: Int64
    public var pattern: String
    public var label: String?
    public var enabled: Bool

    public init(id: Int64 = 0, pattern: String = "", label: String? = nil, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.label = label
        self.enabled = enabled
    }
}

public struct IgnoredApp: Sendable, Equatable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String?

    public init(bundleID: String = "", appName: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
    }
}

public final class IgnoreRulesStore {
    private let database: Database

    public init(database: Database) {
        self.database = database
        try? database.execute("CREATE TABLE IF NOT EXISTS ignore_apps (bundle_id TEXT PRIMARY KEY, app_name TEXT);")
        try? database.execute("CREATE TABLE IF NOT EXISTS ignore_regex_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, pattern TEXT NOT NULL, label TEXT, enabled INTEGER NOT NULL DEFAULT 1);")
    }

    public func ignoredApps() throws -> [IgnoredApp] {
        try database.query("SELECT bundle_id, app_name FROM ignore_apps ORDER BY app_name COLLATE NOCASE, bundle_id COLLATE NOCASE", []).compactMap(Self.ignoredApp)
    }

    public func addIgnoredApp(bundleID: String, appName: String?) throws {
        let appNameValue: SQLValue = appName.map { .text($0) } ?? .null
        try database.run(
            "INSERT INTO ignore_apps (bundle_id, app_name) VALUES (?, ?) ON CONFLICT(bundle_id) DO UPDATE SET app_name = excluded.app_name",
            [.text(bundleID), appNameValue]
        )
    }

    public func removeIgnoredApp(bundleID: String) throws {
        try database.run("DELETE FROM ignore_apps WHERE bundle_id = ?", [.text(bundleID)])
    }

    public func regexRules() throws -> [IgnoreRegexRule] {
        try database.query("SELECT id, pattern, label, enabled FROM ignore_regex_rules ORDER BY id ASC", []).compactMap(Self.regexRule)
    }

    @discardableResult public func addRegexRule(pattern: String, label: String?) throws -> IgnoreRegexRule {
        let labelValue: SQLValue = label.map { .text($0) } ?? .null
        try database.run(
            "INSERT INTO ignore_regex_rules (pattern, label, enabled) VALUES (?, ?, 1)",
            [.text(pattern), labelValue]
        )
        return IgnoreRegexRule(id: database.lastInsertRowID, pattern: pattern, label: label, enabled: true)
    }

    public func setRegexRule(id: Int64, enabled: Bool) throws {
        try database.run("UPDATE ignore_regex_rules SET enabled = ? WHERE id = ?", [.integer(enabled ? 1 : 0), .integer(id)])
    }

    public func removeRegexRule(id: Int64) throws {
        try database.run("DELETE FROM ignore_regex_rules WHERE id = ?", [.integer(id)])
    }

    private static func ignoredApp(from row: [String: SQLValue]) -> IgnoredApp? {
        guard let bundleID = textValue(row["bundle_id"]) else { return nil }
        return IgnoredApp(bundleID: bundleID, appName: textValue(row["app_name"]))
    }

    private static func regexRule(from row: [String: SQLValue]) -> IgnoreRegexRule? {
        guard let id = intValue(row["id"]), let pattern = textValue(row["pattern"]) else { return nil }
        return IgnoreRegexRule(id: id, pattern: pattern, label: textValue(row["label"]), enabled: boolValue(row["enabled"]))
    }

    private static func textValue(_ value: SQLValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .text(let string): return string
        case .integer(let integer): return String(integer)
        case .real(let double): return String(double)
        case .null, .blob(_): return nil
        }
    }

    private static func intValue(_ value: SQLValue?) -> Int64? {
        guard let value else { return nil }
        switch value {
        case .integer(let integer): return integer
        case .text(let string): return Int64(string)
        case .real(let double): return Int64(double)
        case .null, .blob(_): return nil
        }
    }

    private static func boolValue(_ value: SQLValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .integer(let integer): return integer != 0
        case .real(let double): return double != 0
        case .text(let string): return string != "0" && !string.isEmpty
        case .null, .blob(_): return false
        }
    }
}

public struct IgnoreRuleEvaluator: Sendable {
    private let ignoredBundleIDs: Set<String>
    private let regexes: [CompiledRegex]

    public init(ignoredBundleIDs: Set<String>, regexRules: [IgnoreRegexRule]) {
        self.ignoredBundleIDs = ignoredBundleIDs
        self.regexes = regexRules.compactMap { rule in
            guard rule.enabled, let expression = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return CompiledRegex(expression: expression)
        }
    }

    public func shouldIgnore(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }

    public func shouldIgnore(text: String?) -> Bool {
        guard let text else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regexes.contains { $0.expression.firstMatch(in: text, options: [], range: range) != nil }
    }
}

private struct CompiledRegex: @unchecked Sendable {
    let expression: NSRegularExpression
}
