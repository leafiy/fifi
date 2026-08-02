import Combine
import Foundation
import FifiCore
import LeafiyUICore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let store: LeafiySettingsStore<AppSettings>

    nonisolated static func persistedAppLanguage(
        store: LeafiySettingsStore<AppSettings> = .standard(directoryName: "Fifi")
    ) -> AppLanguage {
        AppLanguage(rawValue: store.load().appLanguage) ?? .system
    }

    init(fileURL: URL? = nil) {
        let backingStore: LeafiySettingsStore<AppSettings>
        if let fileURL {
            backingStore = LeafiySettingsStore(fileURL: fileURL)
        } else {
            backingStore = .standard(directoryName: "Fifi")
        }
        self.store = backingStore
        settings = backingStore.load()
        applyLocalization()
    }

    var hasSavedSettings: Bool {
        store.hasSavedSettings
    }

    // MARK: - Persistence

    @discardableResult
    func load() -> AppSettings {
        settings = store.load()
        applyLocalization()
        return settings
    }

    func save() {
        do {
            try store.save(settings)
        } catch {
            NSLog("Failed to save settings: \(String(describing: error))")
        }
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
        try store.save(settings)
        applyLocalization()
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        save()
        applyLocalization()
    }

    /// Returns settings safe to put in a diagnostics report or export file.
    func sanitizedSettings() -> AppSettings {
        Self.sanitized(settings)
    }

    /// Imports settings while retaining existing credentials when the input is
    /// intentionally redacted, as exports and diagnostics are now.
    func replaceSettings(_ imported: AppSettings) {
        var next = imported.normalized()
        if next.quickShare.accessKeyID.isEmpty {
            next.quickShare.accessKeyID = settings.quickShare.accessKeyID
        }
        if next.quickShare.secretAccessKey.isEmpty {
            next.quickShare.secretAccessKey = settings.quickShare.secretAccessKey
        }
        settings = next
        save()
        applyLocalization()
    }

    private static func sanitized(_ settings: AppSettings) -> AppSettings {
        var sanitized = settings
        sanitized.quickShare.accessKeyID = ""
        sanitized.quickShare.secretAccessKey = ""
        return sanitized
    }

    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: settings.appLanguage) ?? .system }
        set {
            update { settings in
                settings.appLanguage = newValue.rawValue
            }
        }
    }

    private func applyLocalization() {
        LeafiyLocalization.language = appLanguage
    }
}
