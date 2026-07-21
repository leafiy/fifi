import Combine
import Foundation
import FifiCore
import LeafiyUICore
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let defaults: UserDefaults
    private let secrets: KeychainSecretStore
    private let key = "app.settings"


    nonisolated static func persistedAppLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let data = defaults.data(forKey: "app.settings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .system
        }
        return AppLanguage(rawValue: settings.appLanguage) ?? .system
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.secrets = KeychainSecretStore()
        if let data = defaults.data(forKey: key) {
            do {
                settings = Self.hydrate(
                    try JSONDecoder().decode(AppSettings.self, from: data),
                    secrets: secrets
                )
            } catch {
                NSLog("Failed to decode settings, using defaults: \(String(describing: error))")
                settings = AppSettings()
            }
        } else {
            settings = Self.hydrate(AppSettings(), secrets: secrets)
        }
        // Rewrite legacy settings immediately so credentials are removed from
        // the UserDefaults blob even if the user makes no further changes.
        save()
        applyLocalization()
    }

    // MARK: - Persistence

    func save() {
        do {
            try persistSecrets(from: settings)
            let data = try JSONEncoder().encode(Self.sanitized(settings))
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Failed to save settings: \(String(describing: error))")
        }
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
        var next = imported
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

    private func persistSecrets(from settings: AppSettings) throws {
        let accessKey = settings.quickShare.accessKeyID
        let secretKey = settings.quickShare.secretAccessKey
        if accessKey.isEmpty {
            try secrets.remove(account: "quickShareAccessKeyID")
        } else {
            try secrets.write(accessKey, account: "quickShareAccessKeyID")
        }
        if secretKey.isEmpty {
            try secrets.remove(account: "quickShareSecretAccessKey")
        } else {
            try secrets.write(secretKey, account: "quickShareSecretAccessKey")
        }
    }

    private static func hydrate(_ settings: AppSettings, secrets: KeychainSecretStore) -> AppSettings {
        var hydrated = settings
        do {
            if let stored = try secrets.read(account: "quickShareAccessKeyID") {
                hydrated.quickShare.accessKeyID = stored
            } else if !hydrated.quickShare.accessKeyID.isEmpty {
                try secrets.write(hydrated.quickShare.accessKeyID, account: "quickShareAccessKeyID")
            }
            if let stored = try secrets.read(account: "quickShareSecretAccessKey") {
                hydrated.quickShare.secretAccessKey = stored
            } else if !hydrated.quickShare.secretAccessKey.isEmpty {
                try secrets.write(hydrated.quickShare.secretAccessKey, account: "quickShareSecretAccessKey")
            }
        } catch {
            NSLog("Fifi: failed to access Keychain: %@", String(describing: error))
        }
        return hydrated
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

    // MARK: - Login Item

    func applyLaunchAtLogin() {
        do {
            let service = SMAppService.mainApp
            if settings.launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Failed to apply launch-at-login setting: \(String(describing: error))")
        }
    }
}
