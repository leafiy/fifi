import Foundation

/// Snapshot of app health for support/debugging exports. Contains no
/// clipboard content — counts, sizes, and configuration only.
public struct DiagnosticsReport: Sendable {
    public var generatedAt: Date
    public var appVersion: String
    public var schemaVersion: Int
    public var itemCount: Int
    public var countsByType: [String: Int]
    public var totalContentBytes: Int
    public var databaseSizeBytes: Int
    public var blobStoreSizeBytes: Int
    public var integrityIssues: [String]
    public var settingsJSON: String

    public init(
        generatedAt: Date,
        appVersion: String,
        schemaVersion: Int,
        itemCount: Int,
        countsByType: [String: Int],
        totalContentBytes: Int,
        databaseSizeBytes: Int,
        blobStoreSizeBytes: Int,
        integrityIssues: [String],
        settingsJSON: String
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.itemCount = itemCount
        self.countsByType = countsByType
        self.totalContentBytes = totalContentBytes
        self.databaseSizeBytes = databaseSizeBytes
        self.blobStoreSizeBytes = blobStoreSizeBytes
        self.integrityIssues = integrityIssues
        self.settingsJSON = settingsJSON
    }

    public func render() -> String {
        var lines: [String] = []
        lines.append("Fifi Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("App version: \(appVersion)")
        lines.append("Schema version: \(schemaVersion)")
        lines.append("")
        lines.append("History")
        lines.append("  Items: \(itemCount)")
        for (type, count) in countsByType.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(type): \(count)")
        }
        lines.append("  Content bytes: \(totalContentBytes)")
        lines.append("  Database file bytes: \(databaseSizeBytes)")
        lines.append("  Blob store bytes: \(blobStoreSizeBytes)")
        lines.append("")
        lines.append("Integrity: \(integrityIssues.isEmpty ? "ok" : integrityIssues.joined(separator: "; "))")
        lines.append("")
        lines.append("Settings")
        lines.append(settingsJSON)
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

public enum Diagnostics {
    public static func collect(
        database: Database,
        historyStore: HistoryStore,
        blobStore: BlobStore,
        settings: AppSettings,
        appVersion: String,
        databasePath: String
    ) -> DiagnosticsReport {
        let counts = (try? historyStore.countsByType()) ?? [:]
        let settingsJSON: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            settingsJSON = String(data: try encoder.encode(settings), encoding: .utf8) ?? "{}"
        } catch {
            settingsJSON = "unavailable: \(error)"
        }

        let databaseSize = (try? FileManager.default.attributesOfItem(atPath: databasePath)[.size] as? Int) ?? 0

        return DiagnosticsReport(
            generatedAt: Date(),
            appVersion: appVersion,
            schemaVersion: (try? SchemaMigrator.userVersion(database)) ?? -1,
            itemCount: (try? historyStore.itemCount()) ?? -1,
            countsByType: Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            totalContentBytes: (try? historyStore.totalBytes()) ?? -1,
            databaseSizeBytes: databaseSize,
            blobStoreSizeBytes: blobStore.totalBytes(),
            integrityIssues: (try? database.integrityCheck()) ?? ["integrity check failed to run"],
            settingsJSON: settingsJSON
        )
    }
}
