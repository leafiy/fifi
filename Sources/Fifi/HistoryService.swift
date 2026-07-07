import AppKit
import Foundation
import FifiCore

@MainActor
final class HistoryService {
    private let historyStore: HistoryStore
    private let databasePath: String
    private let blobStore: BlobStore
    private let settingsProvider: () -> AppSettings
    private let cleanupQueue = DispatchQueue(label: "com.leafiy.fifi.cleanup", qos: .utility)

    // In-memory ring buffer for private-mode / memory-only captures. These are
    // never written to disk; they carry synthetic negative ids so the rest of
    // the app can tell them apart from persisted rows.
    private var memory: [ClipboardItem] = []
    private var nextMemoryID: Int64 = -1
    private let memoryLimit = 50

    init(
        historyStore: HistoryStore,
        databasePath: String,
        blobStore: BlobStore,
        settingsProvider: @escaping () -> AppSettings
    ) {
        self.historyStore = historyStore
        self.databasePath = databasePath
        self.blobStore = blobStore
        self.settingsProvider = settingsProvider
    }

    static func isMemoryItem(_ id: Int64) -> Bool { id < 0 }

    // MARK: - Reads

    func items(matching query: HistoryQuery, limit: Int, offset: Int) -> [ClipboardItem] {
        do {
            return try freshHistoryStore().items(matching: query, limit: limit, offset: offset)
        } catch {
            NSLog("Failed to load filtered history: \(String(describing: error))")
            return []
        }
    }

    func memoryItems(matching query: HistoryQuery) -> [ClipboardItem] {
        memory.filter { matches($0, query: query) }
    }

    var hasMemoryItems: Bool { !memory.isEmpty }

    func distinctSourceApps() -> [SourceAppSummary] {
        do {
            return try freshHistoryStore().distinctSourceApps()
        } catch {
            NSLog("Failed to load source apps: \(String(describing: error))")
            return []
        }
    }

    func usage() -> (count: Int, totalBytes: Int) {
        do {
            return (try historyStore.itemCount(), try historyStore.totalBytes())
        } catch {
            NSLog("Failed to load history usage: \(String(describing: error))")
            return (0, 0)
        }
    }

    // MARK: - Memory captures

    @discardableResult
    func addMemoryItem(_ item: ClipboardItem) -> ClipboardItem {
        var stored = item
        stored.id = nextMemoryID
        nextMemoryID -= 1
        memory.insert(stored, at: 0)
        if memory.count > memoryLimit {
            memory.removeLast(memory.count - memoryLimit)
        }
        return stored
    }

    func clearMemory() {
        memory.removeAll(keepingCapacity: false)
    }

    // MARK: - Mutations

    @discardableResult
    func delete(item: ClipboardItem) -> Bool {
        if Self.isMemoryItem(item.id) {
            memory.removeAll { $0.id == item.id }
            return true
        }
        do {
            guard let deleted = try freshHistoryStore().delete(id: item.id) else {
                NSLog("History item \(item.id) was not found during delete")
                return false
            }
            deleteBlobs(for: deleted)
            return true
        } catch {
            NSLog("Failed to delete history item \(item.id): \(String(describing: error))")
            return false
        }
    }

    @discardableResult
    func togglePin(item: ClipboardItem) -> Bool {
        guard !Self.isMemoryItem(item.id) else { return false }
        do {
            try freshHistoryStore().setPinned(id: item.id, !item.isPinned)
            return true
        } catch {
            NSLog("Failed to toggle pin for item \(item.id): \(String(describing: error))")
            return false
        }
    }

    func clearAll(keepPinned: Bool = false) {
        clearMemory()
        do {
            let deleted = try historyStore.clearAll(keepPinned: keepPinned)
            deleted.forEach(deleteBlobs)
        } catch {
            NSLog("Failed to clear history: \(String(describing: error))")
        }
    }

    func clear(type: ClipItemType) {
        memory.removeAll { $0.type == type }
        do {
            let deleted = try historyStore.clear(type: type)
            deleted.forEach(deleteBlobs)
        } catch {
            NSLog("Failed to clear \(type.rawValue) history: \(String(describing: error))")
        }
    }

    func markUsed(id: Int64) {
        guard !Self.isMemoryItem(id) else { return }
        do {
            try freshHistoryStore().markUsed(id: id)
        } catch {
            NSLog("Failed to mark item \(id) used: \(String(describing: error))")
        }
    }

    // MARK: - Cleanup

    func runCleanup() {
        let policy = settingsProvider().cleanupPolicy
        let historyStore = self.historyStore
        let blobStore = self.blobStore
        cleanupQueue.async {
            do {
                let deleted = try historyStore.cleanup(policy: policy)
                for item in deleted {
                    Self.deleteBlobs(for: item, blobStore: blobStore)
                }
            } catch {
                NSLog("History cleanup failed: \(String(describing: error))")
            }
        }
    }

    /// Deletes entries whose auto-delete deadline has passed. Runs on the main
    /// connection; cheap because it is indexed on `expires_at`.
    @discardableResult
    func deleteExpired() -> Bool {
        do {
            let deleted = try historyStore.deleteExpired()
            deleted.forEach(deleteBlobs)
            return !deleted.isEmpty
        } catch {
            NSLog("Expiry sweep failed: \(String(describing: error))")
            return false
        }
    }

    // MARK: - Backup / diagnostics

    /// Online backup of the database plus a copy of the blob payload
    /// directories into `folder`. Safe to run while the app is live.
    func exportBackup(to folder: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let database = try Database(path: databasePath)
        defer { database.close() }
        try database.backup(toPath: folder.appendingPathComponent("fifi.sqlite3").path)
        for source in blobStore.payloadDirectories {
            let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try? fileManager.removeItem(at: destination)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    func diagnosticsReport(appVersion: String) -> DiagnosticsReport {
        guard let database = try? Database(path: databasePath),
              let store = try? HistoryStore(database: database) else {
            return DiagnosticsReport(
                generatedAt: Date(),
                appVersion: appVersion,
                schemaVersion: -1,
                itemCount: -1,
                countsByType: [:],
                totalContentBytes: -1,
                databaseSizeBytes: 0,
                blobStoreSizeBytes: blobStore.totalBytes(),
                integrityIssues: ["database could not be opened"],
                settingsJSON: "{}"
            )
        }
        defer { database.close() }
        return Diagnostics.collect(
            database: database,
            historyStore: store,
            blobStore: blobStore,
            settings: settingsProvider(),
            appVersion: appVersion,
            databasePath: databasePath
        )
    }

    // MARK: - Memory matching

    private func matches(_ item: ClipboardItem, query: HistoryQuery) -> Bool {
        let filter = query.filter
        if !filter.types.isEmpty, !filter.types.contains(item.type) { return false }
        if !filter.sourceAppBundleIDs.isEmpty {
            guard let bundleID = item.sourceAppBundleID, filter.sourceAppBundleIDs.contains(bundleID) else {
                return false
            }
        }
        if let since = filter.since, item.createdAt < since { return false }
        if let until = filter.until, item.createdAt > until { return false }
        if filter.pinnedOnly { return false } // memory items can't be pinned
        if filter.minUseCount > 0 { return false }

        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let haystack = [item.previewText, item.contentText ?? "", item.fileReference ?? "", item.sourceAppName ?? ""]
            .joined(separator: "\n")
        if query.isRegex {
            guard let expression = try? NSRegularExpression(pattern: text, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
            return expression.firstMatch(in: haystack, options: [], range: range) != nil
        }
        return haystack.range(of: text, options: .caseInsensitive) != nil
    }

    // MARK: - Blobs

    private func deleteBlobs(for item: ClipboardItem) {
        Self.deleteBlobs(for: item, blobStore: blobStore)
    }

    nonisolated private static func deleteBlobs(for item: ClipboardItem, blobStore: BlobStore) {
        if let blobPath = item.blobPath {
            blobStore.delete(relativePath: blobPath)
        }
        if let thumbnailPath = item.thumbnailPath {
            blobStore.delete(relativePath: thumbnailPath)
        }
    }

    private func freshHistoryStore() throws -> HistoryStore {
        let database = try Database(path: databasePath)
        return try HistoryStore(database: database)
    }
}
