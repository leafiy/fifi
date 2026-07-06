import AppKit
import Combine
import Foundation
import FifiCore

@main
enum FifiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: Database?
    private var historyStore: HistoryStore?
    private var blobStore: BlobStore?
    private var ignoreRulesStore: IgnoreRulesStore?
    private var settingsStore: SettingsStore?
    private var historyService: HistoryService?
    private var monitor: ClipboardMonitor?
    private let hotKeyCenter = HotKeyCenter()
    private var pickerController: PickerController?
    private var settingsWindowController: SettingsWindowController?

    private var statusItem: NSStatusItem?
    private var openPickerItem: NSMenuItem?
    private var pauseRecordingItem: NSMenuItem?
    private var cleanupTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var lastRegisteredShortcut: String?
    private var lastLaunchAtLogin: Bool?
    private var lastPauseState: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try configureServices()
        } catch {
            presentStartupFailure(error)
            return
        }

        createStatusItem()
        observeSettings()

        if let settings = settingsStore?.settings {
            apply(settings: settings)
        }

        hotKeyCenter.onActivate = { [weak self] in
            Task { @MainActor in
                self?.pickerController?.toggle()
            }
        }

        scheduleCleanup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTimer?.invalidate()
        monitor?.stop()
        hotKeyCenter.unregister()
        database?.close()
    }

    // MARK: - Setup

    private func configureServices() throws {
        let supportDirectory = try applicationSupportDirectory()
        let databaseURL = supportDirectory.appendingPathComponent("fifi.sqlite3", isDirectory: false)

        let database = try Database(path: databaseURL.path)
        let historyStore = try HistoryStore(database: database)
        let blobStore = try BlobStore(rootDirectory: supportDirectory)
        let ignoreRulesStore = IgnoreRulesStore(database: database)
        let settingsStore = SettingsStore()
        let historyService = HistoryService(
            historyStore: historyStore,
            blobStore: blobStore,
            settingsProvider: { settingsStore.settings }
        )
        let monitor = ClipboardMonitor(
            historyStore: historyStore,
            blobStore: blobStore,
            ignoreRulesStore: ignoreRulesStore,
            settingsStore: settingsStore
        )
        let pickerController = PickerController(
            historyService: historyService,
            blobStore: blobStore,
            settingsStore: settingsStore
        )
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            historyService: historyService,
            ignoreRulesStore: ignoreRulesStore,
            monitorReload: { [weak monitor] in monitor?.reloadIgnoreRules() }
        )

        self.database = database
        self.historyStore = historyStore
        self.blobStore = blobStore
        self.ignoreRulesStore = ignoreRulesStore
        self.settingsStore = settingsStore
        self.historyService = historyService
        self.monitor = monitor
        self.pickerController = pickerController
        self.settingsWindowController = settingsWindowController
    }

    private func applicationSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (base ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true))
            .appendingPathComponent("Fifi", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func presentStartupFailure(_ error: Error) {
        NSLog("Fifi startup failed: \(String(describing: error))")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Fifi couldn’t start"
        alert.informativeText = "The history database could not be opened. Fifi will quit.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    // MARK: - Menu

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Fifi")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        let openPickerItem = NSMenuItem(title: "Open Picker", action: #selector(openPicker), keyEquivalent: "")
        openPickerItem.target = self
        menu.addItem(openPickerItem)

        menu.addItem(.separator())

        let pauseRecordingItem = NSMenuItem(title: "Pause Recording", action: #selector(toggleRecordingPause), keyEquivalent: "")
        pauseRecordingItem.target = self
        menu.addItem(pauseRecordingItem)

        let clearHistoryItem = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

        let clearByTypeItem = NSMenuItem(title: "Clear by Type", action: nil, keyEquivalent: "")
        let clearByTypeMenu = NSMenu()
        for type in ClipItemType.allCases {
            let typeItem = NSMenuItem(title: Self.typeLabel(type), action: #selector(clearHistoryByType(_:)), keyEquivalent: "")
            typeItem.target = self
            typeItem.representedObject = type.rawValue
            clearByTypeMenu.addItem(typeItem)
        }
        clearByTypeItem.submenu = clearByTypeMenu
        menu.addItem(clearByTypeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Fifi", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
        self.openPickerItem = openPickerItem
        self.pauseRecordingItem = pauseRecordingItem
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard let settings = settingsStore?.settings else { return }
        openPickerItem?.title = "Open Picker    \(shortcutDisplay(settings.hotkeyShortcut))"
        pauseRecordingItem?.title = settings.isRecordingPaused ? "Resume Recording" : "Pause Recording"
        pauseRecordingItem?.state = settings.isRecordingPaused ? .on : .off
    }

    @objc private func openPicker() {
        pickerController?.toggle()
    }

    @objc private func toggleRecordingPause() {
        settingsStore?.update { settings in
            settings.isRecordingPaused.toggle()
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items will be kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            historyService?.clearAll(keepPinned: true)
        }
    }

    @objc private func clearHistoryByType(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let type = ClipItemType(rawValue: raw) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all \(Self.typeLabel(type)) items?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            historyService?.clear(type: type)
        }
    }

    private static func typeLabel(_ type: ClipItemType) -> String {
        switch type {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .url: return "URLs"
        case .image: return "Images"
        case .color: return "Colors"
        case .file: return "Files"
        case .unknown: return "Other"
        }
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings

    private func observeSettings() {
        settingsCancellable = settingsStore?.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.apply(settings: settings)
                }
            }
    }

    private func apply(settings: AppSettings) {
        updateStatusMenu()
        registerHotKeyIfNeeded(settings.hotkeyShortcut)
        applyLaunchAtLoginIfNeeded(settings)
        applyRecordingStateIfNeeded(settings)
    }

    private func registerHotKeyIfNeeded(_ shortcut: String) {
        guard lastRegisteredShortcut != shortcut else { return }
        lastRegisteredShortcut = shortcut
        hotKeyCenter.unregister()
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            NSLog("Unsupported hotkey shortcut: \(shortcut)")
            return
        }
        hotKeyCenter.register(shortcut: shortcut)
    }

    private func applyLaunchAtLoginIfNeeded(_ settings: AppSettings) {
        guard lastLaunchAtLogin != settings.launchAtLogin else { return }
        lastLaunchAtLogin = settings.launchAtLogin
        settingsStore?.applyLaunchAtLogin()
    }

    private func applyRecordingStateIfNeeded(_ settings: AppSettings) {
        guard lastPauseState != settings.isRecordingPaused else { return }
        lastPauseState = settings.isRecordingPaused
        if settings.isRecordingPaused {
            monitor?.stop()
        } else {
            monitor?.start()
        }
    }

    private func shortcutDisplay(_ shortcut: String) -> String {
        let symbols: [String: String] = [
            "cmd": "⌘",
            "command": "⌘",
            "shift": "⇧",
            "option": "⌥",
            "alt": "⌥",
            "ctrl": "⌃",
            "control": "⌃"
        ]
        let parts = shortcut
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let modifiers = parts.dropLast().map { symbols[$0] ?? $0.uppercased() }.joined()
        let key = parts.last.map { $0.uppercased() } ?? ""
        return modifiers + key
    }

    // MARK: - Cleanup

    private func scheduleCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.historyService?.runCleanup()
        }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.historyService?.runCleanup()
            }
        }
    }
}
