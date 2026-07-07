import Foundation

// @unchecked: stateless besides an immutable reference to the internally-locked Database.
public final class HistoryStore: @unchecked Sendable {
    private let database: Database

    public init(database: Database) throws {
        self.database = database
        try SchemaMigrator.migrate(database)
    }

    @discardableResult
    public func save(_ item: NewClipboardItem) throws -> ClipboardItem {
        try database.transaction {
            let now = Date().timeIntervalSince1970
            if let existing = try self.item(contentHash: item.contentHash) {
                try database.run(
                    """
                    UPDATE clipboard_items
                    SET updated_at = ?, use_count = use_count + 1, source_app_name = ?, source_app_bundle_id = ?,
                        is_sensitive = ?, expires_at = ?
                    WHERE id = ?
                    """,
                    [
                        .real(now),
                        optionalText(item.sourceAppName),
                        optionalText(item.sourceAppBundleID),
                        .integer(item.isSensitive ? 1 : 0),
                        item.expiresAt.map { SQLValue.real($0.timeIntervalSince1970) } ?? .null,
                        .integer(existing.id)
                    ]
                )
                try replaceSearchText(item.searchText, rowID: existing.id)
                guard let updated = try self.item(id: existing.id) else { throw HistoryStoreError.missingSavedItem }
                return updated
            }

            try database.run(
                """
                INSERT INTO clipboard_items (
                    content_hash, type, preview_text, content_text, source_app_name, source_app_bundle_id,
                    created_at, updated_at, last_used_at, use_count, is_pinned, is_sensitive, expires_at,
                    byte_size, blob_path, thumbnail_path, file_reference, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(item.contentHash),
                    .text(item.type.rawValue),
                    .text(item.previewText),
                    optionalText(item.contentText),
                    optionalText(item.sourceAppName),
                    optionalText(item.sourceAppBundleID),
                    .real(now),
                    .real(now),
                    .null,
                    .integer(0),
                    .integer(0),
                    .integer(item.isSensitive ? 1 : 0),
                    item.expiresAt.map { SQLValue.real($0.timeIntervalSince1970) } ?? .null,
                    .integer(Int64(item.byteSize)),
                    optionalText(item.blobPath),
                    optionalText(item.thumbnailPath),
                    optionalText(item.fileReference),
                    optionalText(item.metadataJSON)
                ]
            )
            let id = database.lastInsertRowID
            try replaceSearchText(item.searchText, rowID: id)
            guard let saved = try self.item(id: id) else { throw HistoryStoreError.missingSavedItem }
            return saved
        }
    }

    public func item(id: Int64) throws -> ClipboardItem? {
        try database.query(
            "SELECT \(Self.itemColumns()) FROM clipboard_items WHERE id = ? LIMIT 1",
            [.integer(id)]
        ).first.map(item(from:))
    }

    public func recentItems(limit: Int, offset: Int) throws -> [ClipboardItem] {
        try database.query(
            """
            SELECT \(Self.itemColumns())
            FROM clipboard_items
            ORDER BY is_pinned DESC, updated_at DESC
            LIMIT ? OFFSET ?
            """,
            [.integer(Int64(max(0, limit))), .integer(Int64(max(0, offset)))]
        ).map(item(from:))
    }

    public func search(_ query: String, limit: Int, offset: Int) throws -> [ClipboardItem] {
        let match = Self.sanitizedFTSQuery(query)
        guard !match.isEmpty else {
            return try recentItems(limit: limit, offset: offset)
        }

        return try database.query(
            """
            SELECT \(Self.itemColumns(prefix: "i."))
            FROM clipboard_items i
            JOIN clipboard_items_fts f ON f.rowid = i.id
            WHERE clipboard_items_fts MATCH ?
            ORDER BY i.is_pinned DESC, i.updated_at DESC
            LIMIT ? OFFSET ?
            """,
            [.text(match), .integer(Int64(max(0, limit))), .integer(Int64(max(0, offset)))]
        ).map(item(from:))
    }

    public func markUsed(id: Int64) throws {
        let now = Date().timeIntervalSince1970
        try database.run(
            """
            UPDATE clipboard_items
            SET last_used_at = ?, use_count = use_count + 1, updated_at = ?
            WHERE id = ?
            """,
            [.real(now), .real(now), .integer(id)]
        )
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        try database.run(
            "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?",
            [.integer(pinned ? 1 : 0), .integer(id)]
        )
    }

    public func delete(id: Int64) throws -> ClipboardItem? {
        try database.transaction {
            guard let item = try self.item(id: id) else { return nil }
            try deleteStoredItem(id: id)
            return item
        }
    }

    public func clearAll(keepPinned: Bool) throws -> [ClipboardItem] {
        try database.transaction {
            let whereClause = keepPinned ? "WHERE is_pinned = 0" : ""
            let removed = try database.query(
                "SELECT \(Self.itemColumns()) FROM clipboard_items \(whereClause) ORDER BY updated_at ASC, id ASC",
                []
            ).map(item(from:))

            if keepPinned {
                try database.run(
                    "DELETE FROM clipboard_items_fts WHERE rowid IN (SELECT id FROM clipboard_items WHERE is_pinned = 0)",
                    []
                )
                try database.run("DELETE FROM clipboard_items WHERE is_pinned = 0", [])
            } else {
                try database.run("DELETE FROM clipboard_items_fts", [])
                try database.run("DELETE FROM clipboard_items", [])
            }
            return removed
        }
    }

    public func clear(type: ClipItemType) throws -> [ClipboardItem] {
        try database.transaction {
            let removed = try database.query(
                "SELECT \(Self.itemColumns()) FROM clipboard_items WHERE type = ? ORDER BY updated_at ASC, id ASC",
                [.text(type.rawValue)]
            ).map(item(from:))
            try database.run(
                "DELETE FROM clipboard_items_fts WHERE rowid IN (SELECT id FROM clipboard_items WHERE type = ?)",
                [.text(type.rawValue)]
            )
            try database.run("DELETE FROM clipboard_items WHERE type = ?", [.text(type.rawValue)])
            return removed
        }
    }

    public func itemCount() throws -> Int {
        try countRows()
    }

    public func totalBytes() throws -> Int {
        try totalByteCount()
    }

    public func cleanup(policy: CleanupPolicy) throws -> [ClipboardItem] {
        try database.transaction {
            var removed: [ClipboardItem] = []

            // Expired sensitive entries are removed unconditionally, pins included.
            removed.append(contentsOf: try removeItems(
                matching: "expires_at IS NOT NULL AND expires_at <= ?",
                bindings: [.real(Date().timeIntervalSince1970)]
            ))

            if let days = policy.maxAgeDays {
                let cutoff = Date().timeIntervalSince1970 - Double(max(0, days)) * 86_400
                removed.append(contentsOf: try removeItems(
                    matching: "is_pinned = 0 AND updated_at < ?",
                    bindings: [.real(cutoff)]
                ))
            }

            if let maxCount = policy.maxCount {
                // Pinned items are exempt from cleanup and never count toward the cap.
                let unpinnedRows = try database.query(
                    "SELECT COUNT(*) AS n FROM clipboard_items WHERE is_pinned = 0", []
                )
                let unpinnedCount = unpinnedRows.first.flatMap { row -> Int? in
                    if case let .integer(n)? = row["n"] { return Int(n) } else { return nil }
                } ?? 0
                let overflow = unpinnedCount - max(0, maxCount)
                if overflow > 0 {
                    let rows = try database.query(
                        """
                        SELECT \(Self.itemColumns())
                        FROM clipboard_items
                        WHERE is_pinned = 0
                        ORDER BY updated_at ASC, id ASC
                        LIMIT ?
                        """,
                        [.integer(Int64(overflow))]
                    )
                    for item in rows.map(item(from:)) {
                        try deleteStoredItem(id: item.id)
                        removed.append(item)
                    }
                }
            }

            if let maxTotalBytes = policy.maxTotalBytes {
                let limit = max(0, maxTotalBytes)
                var total = try totalByteCount()
                if total > limit {
                    let rows = try database.query(
                        """
                        SELECT \(Self.itemColumns())
                        FROM clipboard_items
                        WHERE is_pinned = 0
                        ORDER BY updated_at ASC, id ASC
                        """,
                        []
                    )
                    for item in rows.map(item(from:)) {
                        guard total > limit else { break }
                        try deleteStoredItem(id: item.id)
                        total -= item.byteSize
                        removed.append(item)
                    }
                }
            }

            return removed
        }
    }

    /// Deletes entries whose auto-delete deadline has passed, pins included.
    public func deleteExpired(reference: Date = Date()) throws -> [ClipboardItem] {
        try database.transaction {
            try removeItems(
                matching: "expires_at IS NOT NULL AND expires_at <= ?",
                bindings: [.real(reference.timeIntervalSince1970)]
            )
        }
    }

    // MARK: - Filtered queries

    public func items(matching query: HistoryQuery, limit: Int, offset: Int) throws -> [ClipboardItem] {
        var clauses: [String] = []
        var bindings: [SQLValue] = []
        var joinsFTS = false

        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if query.isRegex {
                joinsFTS = true
                clauses.append("f.content REGEXP ?")
                bindings.append(.text(text))
            } else {
                let match = Self.sanitizedFTSQuery(text)
                if !match.isEmpty {
                    joinsFTS = true
                    clauses.append("clipboard_items_fts MATCH ?")
                    bindings.append(.text(match))
                }
            }
        }

        let filter = query.filter
        if !filter.types.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.types.count).joined(separator: ", ")
            clauses.append("i.type IN (\(placeholders))")
            bindings.append(contentsOf: filter.types.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) })
        }
        if !filter.sourceAppBundleIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.sourceAppBundleIDs.count).joined(separator: ", ")
            clauses.append("i.source_app_bundle_id IN (\(placeholders))")
            bindings.append(contentsOf: filter.sourceAppBundleIDs.sorted().map(SQLValue.text))
        }
        if let since = filter.since {
            clauses.append("i.created_at >= ?")
            bindings.append(.real(since.timeIntervalSince1970))
        }
        if let until = filter.until {
            clauses.append("i.created_at <= ?")
            bindings.append(.real(until.timeIntervalSince1970))
        }
        if filter.pinnedOnly {
            clauses.append("i.is_pinned = 1")
        }
        if filter.minUseCount > 0 {
            clauses.append("i.use_count >= ?")
            bindings.append(.integer(Int64(filter.minUseCount)))
        }

        let join = joinsFTS ? "JOIN clipboard_items_fts f ON f.rowid = i.id" : ""
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let orderClause: String
        switch query.sort {
        case .recency:
            orderClause = "ORDER BY i.is_pinned DESC, i.updated_at DESC"
        case .mostUsed:
            orderClause = "ORDER BY i.use_count DESC, COALESCE(i.last_used_at, 0) DESC, i.updated_at DESC"
        }

        // Fuzzy ranking re-orders a bounded candidate pool client-side; the
        // pool must cover the requested window plus headroom for re-ranking.
        let usesFuzzy = query.fuzzyRanking && !query.isRegex && !text.isEmpty && joinsFTS
        let fetchLimit = usesFuzzy ? max(limit + offset, 400) : max(0, limit)
        let fetchOffset = usesFuzzy ? 0 : max(0, offset)

        let rows = try database.query(
            """
            SELECT \(Self.itemColumns(prefix: "i."))
            FROM clipboard_items i
            \(join)
            \(whereClause)
            \(orderClause)
            LIMIT ? OFFSET ?
            """,
            bindings + [.integer(Int64(fetchLimit)), .integer(Int64(fetchOffset))]
        )
        var items = rows.map(item(from:))

        if usesFuzzy {
            let scored = items.enumerated().map { pair -> (offset: Int, item: ClipboardItem, score: Double) in
                let score = FuzzyScorer.score(query: text, candidate: pair.element.previewText) ?? -Double.infinity
                return (pair.offset, pair.element, score)
            }
            items = scored.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.offset < rhs.offset
            }.map(\.item)
            let window = items.dropFirst(max(0, offset)).prefix(max(0, limit))
            items = Array(window)
        }

        return items
    }

    public func distinctSourceApps() throws -> [SourceAppSummary] {
        try database.query(
            """
            SELECT source_app_bundle_id AS bundle_id, MAX(source_app_name) AS app_name, COUNT(*) AS n
            FROM clipboard_items
            WHERE source_app_bundle_id IS NOT NULL AND source_app_bundle_id != ''
            GROUP BY source_app_bundle_id
            ORDER BY n DESC
            """,
            []
        ).compactMap { row in
            guard let bundleID = string(row, "bundle_id") else { return nil }
            return SourceAppSummary(bundleID: bundleID, appName: string(row, "app_name"), itemCount: int(row, "n"))
        }
    }

    public func countsByType() throws -> [ClipItemType: Int] {
        var counts: [ClipItemType: Int] = [:]
        let rows = try database.query(
            "SELECT type, COUNT(*) AS n FROM clipboard_items GROUP BY type", []
        )
        for row in rows {
            guard let raw = string(row, "type"), let type = ClipItemType(rawValue: raw) else { continue }
            counts[type] = int(row, "n")
        }
        return counts
    }

    // MARK: - Queries

    private static func itemColumns(prefix: String = "") -> String {
        [
            "id", "content_hash", "type", "preview_text", "content_text", "source_app_name",
            "source_app_bundle_id", "created_at", "updated_at", "last_used_at", "use_count",
            "is_pinned", "is_sensitive", "expires_at", "byte_size", "blob_path", "thumbnail_path",
            "file_reference", "metadata_json"
        ].map { "\(prefix)\($0) AS \($0)" }.joined(separator: ", ")
    }

    private func item(contentHash: String) throws -> ClipboardItem? {
        try database.query(
            "SELECT \(Self.itemColumns()) FROM clipboard_items WHERE content_hash = ? LIMIT 1",
            [.text(contentHash)]
        ).first.map(item(from:))
    }

    private func replaceSearchText(_ text: String, rowID: Int64) throws {
        try database.run("DELETE FROM clipboard_items_fts WHERE rowid = ?", [.integer(rowID)])
        try database.run(
            "INSERT INTO clipboard_items_fts(rowid, content) VALUES (?, ?)",
            [.integer(rowID), .text(text)]
        )
    }

    private func deleteStoredItem(id: Int64) throws {
        try database.run("DELETE FROM clipboard_items_fts WHERE rowid = ?", [.integer(id)])
        try database.run("DELETE FROM clipboard_items WHERE id = ?", [.integer(id)])
    }

    private func removeItems(matching clause: String, bindings: [SQLValue]) throws -> [ClipboardItem] {
        let rows = try database.query(
            "SELECT \(Self.itemColumns()) FROM clipboard_items WHERE \(clause) ORDER BY updated_at ASC, id ASC",
            bindings
        )
        let items = rows.map(item(from:))
        for item in items {
            try deleteStoredItem(id: item.id)
        }
        return items
    }

    private func countRows() throws -> Int {
        let rows = try database.query("SELECT COUNT(*) AS count FROM clipboard_items", [])
        return int(rows.first, "count")
    }

    private func totalByteCount() throws -> Int {
        let rows = try database.query("SELECT COALESCE(SUM(byte_size), 0) AS bytes FROM clipboard_items", [])
        return int(rows.first, "bytes")
    }

    // MARK: - Mapping

    private func item(from row: [String: SQLValue]) -> ClipboardItem {
        ClipboardItem(
            id: int64(row, "id"),
            contentHash: string(row, "content_hash") ?? "",
            type: ClipItemType(rawValue: string(row, "type") ?? "") ?? .unknown,
            previewText: string(row, "preview_text") ?? "",
            contentText: string(row, "content_text"),
            sourceAppName: string(row, "source_app_name"),
            sourceAppBundleID: string(row, "source_app_bundle_id"),
            createdAt: date(row, "created_at"),
            updatedAt: date(row, "updated_at"),
            lastUsedAt: optionalDate(row, "last_used_at"),
            useCount: int(row, "use_count"),
            isPinned: int(row, "is_pinned") != 0,
            isSensitive: int(row, "is_sensitive") != 0,
            expiresAt: optionalDate(row, "expires_at"),
            byteSize: int(row, "byte_size"),
            blobPath: string(row, "blob_path"),
            thumbnailPath: string(row, "thumbnail_path"),
            fileReference: string(row, "file_reference"),
            metadataJSON: string(row, "metadata_json")
        )
    }

    private func string(_ row: [String: SQLValue], _ key: String) -> String? {
        switch row[key] {
        case .text(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        default: return nil
        }
    }

    private func int64(_ row: [String: SQLValue], _ key: String) -> Int64 {
        switch row[key] {
        case .integer(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value) ?? 0
        default: return 0
        }
    }

    private func int(_ row: [String: SQLValue]?, _ key: String) -> Int {
        guard let row else { return 0 }
        return Int(int64(row, key))
    }

    private func int(_ row: [String: SQLValue], _ key: String) -> Int {
        Int(int64(row, key))
    }

    private func double(_ row: [String: SQLValue], _ key: String) -> Double? {
        switch row[key] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        case .text(let value): return Double(value)
        default: return nil
        }
    }

    private func date(_ row: [String: SQLValue], _ key: String) -> Date {
        Date(timeIntervalSince1970: double(row, key) ?? 0)
    }

    private func optionalDate(_ row: [String: SQLValue], _ key: String) -> Date? {
        guard let value = double(row, key) else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func optionalText(_ value: String?) -> SQLValue {
        value.map(SQLValue.text) ?? .null
    }

    // MARK: - Search

    private static func sanitizedFTSQuery(_ query: String) -> String {
        // Non-search scalars act as separators (matching unicode61 tokenization),
        // so "unique-delete" queries the tokens "unique" and "delete".
        var tokens: [String] = []
        var current = ""
        for scalar in query.unicodeScalars {
            if isSearchScalar(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private static func isSearchScalar(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.alphanumerics.contains(scalar) {
            return true
        }

        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x3040...0x30FF,
             0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}

public enum HistorySortOrder: String, CaseIterable, Sendable, Codable {
    case recency, mostUsed = "most_used"
}

public struct HistoryFilter: Sendable, Equatable {
    /// Empty means all types.
    public var types: Set<ClipItemType>
    /// Empty means all source apps.
    public var sourceAppBundleIDs: Set<String>
    public var since: Date?
    public var until: Date?
    public var pinnedOnly: Bool
    public var minUseCount: Int

    public init(
        types: Set<ClipItemType> = [],
        sourceAppBundleIDs: Set<String> = [],
        since: Date? = nil,
        until: Date? = nil,
        pinnedOnly: Bool = false,
        minUseCount: Int = 0
    ) {
        self.types = types
        self.sourceAppBundleIDs = sourceAppBundleIDs
        self.since = since
        self.until = until
        self.pinnedOnly = pinnedOnly
        self.minUseCount = minUseCount
    }
}

public struct HistoryQuery: Sendable, Equatable {
    public var text: String
    public var isRegex: Bool
    public var filter: HistoryFilter
    public var sort: HistorySortOrder
    public var fuzzyRanking: Bool

    public init(
        text: String = "",
        isRegex: Bool = false,
        filter: HistoryFilter = HistoryFilter(),
        sort: HistorySortOrder = .recency,
        fuzzyRanking: Bool = false
    ) {
        self.text = text
        self.isRegex = isRegex
        self.filter = filter
        self.sort = sort
        self.fuzzyRanking = fuzzyRanking
    }
}

public struct SourceAppSummary: Sendable, Equatable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let appName: String?
    public let itemCount: Int

    public init(bundleID: String, appName: String?, itemCount: Int) {
        self.bundleID = bundleID
        self.appName = appName
        self.itemCount = itemCount
    }
}

public struct CleanupPolicy: Sendable {
    public var maxCount: Int?
    public var maxAgeDays: Int?
    public var maxTotalBytes: Int?

    public init(maxCount: Int? = nil, maxAgeDays: Int? = nil, maxTotalBytes: Int? = nil) {
        self.maxCount = maxCount
        self.maxAgeDays = maxAgeDays
        self.maxTotalBytes = maxTotalBytes
    }
}

private enum HistoryStoreError: Error {
    case missingSavedItem
}
