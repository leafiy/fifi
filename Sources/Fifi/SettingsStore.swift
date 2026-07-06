import Combine
import Foundation
import FifiCore
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let defaults: UserDefaults
    private let key = "app.settings"

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
