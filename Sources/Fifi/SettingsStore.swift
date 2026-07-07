import Combine
import Foundation
import FifiCore
import LeafiyUICore
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let defaults: UserDefaults
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
        if let data = defaults.data(forKey: key) {
            do {
                settings = try JSONDecoder().decode(AppSettings.self, from: data)
            } catch {
                NSLog("Failed to decode settings, using defaults: \(String(describing: error))")
                settings = AppSettings()
            }
        } else {
            settings = AppSettings()
        }
        applyLocalization()
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(settings)
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
