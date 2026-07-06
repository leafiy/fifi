import AppKit
import Foundation
import FifiCore

@MainActor
final class HistoryService {
    private let historyStore: HistoryStore
    private let blobStore: BlobStore
    private let settingsProvider: () -> AppSettings
    private let cleanupQueue = DispatchQueue(label: "com.leafiy.fifi.cleanup", qos: .utility)

    init(
        historyStore: HistoryStore,
        blobStore: BlobStore,
        settingsProvider: @escaping () -> AppSettings
    ) {
        self.historyStore = historyStore
        self.blobStore = blobStore
        self.settingsProvider = settingsProvider
    }

    // MARK: - Reads

    func recent(limit: Int, offset: Int) -> [ClipboardItem] {
        do {
            return try historyStore.recentItems(limit: limit, offset: offset)
        } catch {
            NSLog("Failed to load recent history: \(String(describing: error))")
            return []
        }
    }

    func search(_ query: String, limit: Int, offset: Int) -> [ClipboardItem] {
        do {
            return try historyStore.search(query, limit: limit, offset: offset)
        } catch {
            NSLog("Failed to search history: \(String(describing: error))")
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

    // MARK: - Mutations

    func delete(item: ClipboardItem) {
        do {
            if let deleted = try historyStore.delete(id: item.id) {
                deleteBlobs(for: deleted)
            }
        } catch {
            NSLog("Failed to delete history item \(item.id): \(String(describing: error))")
        }
    }

    func togglePin(item: ClipboardItem) {
        do {
            try historyStore.setPinned(id: item.id, !item.isPinned)
        } catch {
            NSLog("Failed to toggle pin for item \(item.id): \(String(describing: error))")
        }
    }

    func clearAll(keepPinned: Bool = false) {
        do {
            let deleted = try historyStore.clearAll(keepPinned: keepPinned)
            deleted.forEach(deleteBlobs)
        } catch {
            NSLog("Failed to clear history: \(String(describing: error))")
        }
    }

    func clear(type: ClipItemType) {
        do {
            let deleted = try historyStore.clear(type: type)
            deleted.forEach(deleteBlobs)
        } catch {
            NSLog("Failed to clear \(type.rawValue) history: \(String(describing: error))")
        }
    }

    func markUsed(id: Int64) {
        do {
            try historyStore.markUsed(id: id)
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

    // MARK: - Blobs

    private func deleteBlobs(for item: ClipboardItem) {
        Self.deleteBlobs(for: item, blobStore: blobStore)
    }

    private static func deleteBlobs(for item: ClipboardItem, blobStore: BlobStore) {
        if let blobPath = item.blobPath {
            blobStore.delete(relativePath: blobPath)
        }
        if let thumbnailPath = item.thumbnailPath {
            blobStore.delete(relativePath: thumbnailPath)
        }
    }
}
