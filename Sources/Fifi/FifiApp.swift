import AppKit
import Combine
import FifiCore
import LeafiyUI
import LeafiyUICore
import SwiftUI
import UniformTypeIdentifiers

@main
struct FifiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = FifiAppState.shared

    var body: some Scene {
        // The menu bar icon is an NSStatusItem (see AppDelegate): left click
        // must open the picker directly and right click the menu, which
        // MenuBarExtra cannot distinguish.
        Settings {
            FifiSettingsView(appState: appState)
        }
    }
}

@MainActor
final class FifiAppState: ObservableObject {
    static let shared = FifiAppState()

    @Published var settingsStore: SettingsStore?
    @Published var historyService: HistoryService?
    @Published var ignoreRulesStore: IgnoreRulesStore?
    @Published var appPrivacyStore: AppPrivacyStore?
    @Published var hotkeyRegistrationMessage: String?
    @Published var dataActionMessage: String?

    private var monitorReloadHandler: () -> Void = {}
    private var restoreHandler: (URL) -> Void = { _ in }
    private var supportDirectory: URL?

    private init() {}

    func configure(
        settingsStore: SettingsStore,
        historyService: HistoryService,
        ignoreRulesStore: IgnoreRulesStore,
        appPrivacyStore: AppPrivacyStore,
        supportDirectory: URL,
        monitorReload: @escaping () -> Void,
        restoreHandler: @escaping (URL) -> Void
    ) {
        self.settingsStore = settingsStore
        self.historyService = historyService
        self.ignoreRulesStore = ignoreRulesStore
        self.appPrivacyStore = appPrivacyStore
        self.supportDirectory = supportDirectory
        self.monitorReloadHandler = monitorReload
        self.restoreHandler = restoreHandler
    }

    func reloadMonitor() {
        monitorReloadHandler()
    }

    func clearHistoryKeepingPinned(refresh: (() -> Void)? = nil) {
        guard confirmClearHistory() else { return }
        historyService?.clearAll(keepPinned: true)
        refresh?()
    }

    func clearHistory(type: ClipItemType) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all \(type.fifiLabel) items?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            historyService?.clear(type: type)
        }
    }

    private func confirmClearHistory() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items will be kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Import / export / backup / diagnostics

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    func exportSettings() {
        guard let settingsStore, let ignoreRulesStore else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fifi-settings.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let export = SettingsExport(
                settings: settingsStore.settings,
                ignoredApps: (try? ignoreRulesStore.ignoredApps()) ?? [],
                ignoreRegexRules: (try? ignoreRulesStore.regexRules()) ?? [],
                appPrivacyRules: (try? appPrivacyStore?.rules() ?? []) ?? []
            )
            try SettingsCodec.encode(export).write(to: url)
            dataActionMessage = "Settings exported."
        } catch {
            dataActionMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func importSettings() {
        guard let settingsStore, let ignoreRulesStore else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let export = try SettingsCodec.decode(try Data(contentsOf: url))
            settingsStore.update { $0 = export.settings }
            for app in export.ignoredApps {
                try? ignoreRulesStore.addIgnoredApp(bundleID: app.bundleID, appName: app.appName)
            }
            for rule in export.ignoreRegexRules {
                _ = try? ignoreRulesStore.addRegexRule(pattern: rule.pattern, label: rule.label)
            }
            for rule in export.appPrivacyRules {
                try? appPrivacyStore?.setRule(bundleID: rule.bundleID, appName: rule.appName, mode: rule.mode)
            }
            reloadMonitor()
            dataActionMessage = "Settings imported."
        } catch {
            dataActionMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func backupHistory() {
        guard let historyService else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Back Up Here"
        panel.message = "Choose a folder for the Fifi backup."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let folder = base.appendingPathComponent("Fifi Backup", isDirectory: true)
        do {
            try historyService.exportBackup(to: folder)
            dataActionMessage = "Backed up to \(folder.path)."
        } catch {
            dataActionMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    func restoreHistory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Restore"
        panel.message = "Choose a Fifi backup folder. Fifi will relaunch."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore from backup?"
        alert.informativeText = "This replaces all current history and relaunches Fifi."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restoreHandler(folder)
    }

    func exportDiagnostics() {
        guard let historyService else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fifi-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = historyService.diagnosticsReport(appVersion: Self.appVersion)
        do {
            try report.render().write(to: url, atomically: true, encoding: .utf8)
            dataActionMessage = "Diagnostics exported."
        } catch {
            dataActionMessage = "Diagnostics export failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: Database?
    private var historyStore: HistoryStore?
    private var blobStore: BlobStore?
    private var ignoreRulesStore: IgnoreRulesStore?
    private var appPrivacyStore: AppPrivacyStore?
    private var settingsStore: SettingsStore?
    private var historyService: HistoryService?
    private var monitor: ClipboardMonitor?
    private let hotKeyCenter = HotKeyCenter()
    private var pickerController: PickerController?

    private let appState = FifiAppState.shared
    private var cleanupTimer: Timer?
    private var expiryTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var lastRegisteredShortcut: String?
    private var lastLaunchAtLogin: Bool?
    private var lastPauseState: Bool?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var openPickerItem: NSMenuItem?
    private var pauseRecordingItem: NSMenuItem?
    private var warnedHotkeyConflict = false
    private var lastAppearance: AppearanceMode?
    private var lastEncryptBlobs: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let image = Self.fifiImage() {
            NSApp.applicationIconImage = image
        }

        do {
            try configureServices()
        } catch {
            presentStartupFailure(error)
            return
        }

        createStatusItem()

        // Callbacks must be wired before apply(settings:) registers the hotkey,
        // or a launch-time registration failure fires into nil.
        hotKeyCenter.onActivate = { [weak self] in
            // Called synchronously from the Carbon handler on the main thread;
            // stay synchronous so activation keeps its user-event context.
            MainActor.assumeIsolated {
                self?.pickerController?.toggle()
            }
        }
        hotKeyCenter.onRegisterFailed = { [weak self] shortcut, status in
            MainActor.assumeIsolated {
                self?.warnHotkeyConflict(shortcut: shortcut, status: status)
            }
        }

        observeSettings()
        if let settings = settingsStore?.settings {
            apply(settings: settings)
        }

        scheduleCleanup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTimer?.invalidate()
        expiryTimer?.invalidate()
        monitor?.stop()
        hotKeyCenter.unregister()
        database?.close()
    }

    // MARK: - Setup

    private func configureServices() throws {
        let supportDirectory = try applicationSupportDirectory()
        let databaseURL = supportDirectory.appendingPathComponent("fifi.sqlite3", isDirectory: false)

        let database = try Self.openDatabaseWithRecovery(at: databaseURL)
        let historyStore = try HistoryStore(database: database)
        let blobStore = try BlobStore(rootDirectory: supportDirectory)
        let ignoreRulesStore = IgnoreRulesStore(database: database)
        let appPrivacyStore = AppPrivacyStore(database: database)
        let settingsStore = SettingsStore()
        let historyService = HistoryService(
            historyStore: historyStore,
            databasePath: databaseURL.path,
            blobStore: blobStore,
            settingsProvider: { settingsStore.settings }
        )
        let monitor = ClipboardMonitor(
            historyStore: historyStore,
            blobStore: blobStore,
            ignoreRulesStore: ignoreRulesStore,
            appPrivacyStore: appPrivacyStore,
            settingsStore: settingsStore,
            memorySink: { [weak historyService] item in historyService?.addMemoryItem(item) }
        )
        let pickerController = PickerController(
            historyService: historyService,
            blobStore: blobStore,
            settingsStore: settingsStore,
            captureCurrentPasteboard: { [weak monitor] in
                monitor?.captureCurrentPasteboardIfNeeded()
            }
        )

        self.database = database
        self.historyStore = historyStore
        self.blobStore = blobStore
        self.ignoreRulesStore = ignoreRulesStore
        self.appPrivacyStore = appPrivacyStore
        self.settingsStore = settingsStore
        self.historyService = historyService
        self.monitor = monitor
        self.pickerController = pickerController

        appState.configure(
            settingsStore: settingsStore,
            historyService: historyService,
            ignoreRulesStore: ignoreRulesStore,
            appPrivacyStore: appPrivacyStore,
            supportDirectory: supportDirectory,
            monitorReload: { [weak monitor] in monitor?.reloadIgnoreRules() },
            restoreHandler: { [weak self] url in self?.performRestore(from: url) }
        )
    }

    /// Opens the database, verifies integrity, and rebuilds from scratch if the
    /// file is corrupt (moving the bad file aside for post-mortem).
    private static func openDatabaseWithRecovery(at url: URL) throws -> Database {
        let database: Database
        do {
            database = try Database(path: url.path)
            let issues = try database.integrityCheck()
            if issues.isEmpty {
                return database
            }
            NSLog("Fifi database integrity check failed: \(issues.joined(separator: "; "))")
            database.close()
        } catch {
            NSLog("Fifi database open failed, rebuilding: \(String(describing: error))")
        }
        let corruptURL = url.deletingLastPathComponent()
            .appendingPathComponent("fifi-corrupt-\(Int(Date().timeIntervalSince1970)).sqlite3")
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.moveItem(at: source, to: URL(fileURLWithPath: corruptURL.path + suffix))
        }
        return try Database(path: url.path)
    }

    /// Restores history from a backup folder: closes live connections, copies
    /// the backup files over the live ones, then relaunches.
    private func performRestore(from folder: URL) {
        guard let supportDirectory = try? applicationSupportDirectory() else { return }
        let fileManager = FileManager.default
        let backupDB = folder.appendingPathComponent("fifi.sqlite3")
        guard fileManager.fileExists(atPath: backupDB.path) else {
            NSLog("Fifi restore: no fifi.sqlite3 in backup folder")
            return
        }
        monitor?.stop()
        database?.close()
        let liveDB = supportDirectory.appendingPathComponent("fifi.sqlite3")
        for suffix in ["-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: liveDB.path + suffix))
        }
        try? fileManager.removeItem(at: liveDB)
        try? fileManager.copyItem(at: backupDB, to: liveDB)
        for name in ["blobs", "thumbnails"] {
            let source = folder.appendingPathComponent(name, isDirectory: true)
            let destination = supportDirectory.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.removeItem(at: destination)
                try? fileManager.copyItem(at: source, to: destination)
            }
        }
        relaunch()
    }

    private func relaunch() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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

    static func fifiImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "fifi", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "Fifi")
    }

    private func warnHotkeyConflict(shortcut: String, status: OSStatus) {
        let display = KeyboardShortcutSpec(parsing: shortcut)?.display ?? shortcut
        appState.hotkeyRegistrationMessage = "Couldn’t register \(display) (error \(status)); another app may already own it."
        guard !warnedHotkeyConflict else { return }
        warnedHotkeyConflict = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Picker shortcut unavailable"
        alert.informativeText = "Fifi couldn’t register “\(shortcut)” (error \(status)) — another app probably owns it. You can still open the picker by clicking the Fifi menu bar icon, or pick a different shortcut in Settings. This shortcut only opens the picker; copying with ⌘C is always recorded automatically."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Status item

    /// Left click opens the picker directly; right click (or ⌃-click) shows
    /// the menu. MenuBarExtra cannot distinguish the two, so this stays an
    /// NSStatusItem with a transiently attached menu.
    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = Self.fifiImage()?.leafiyMenuBarSized()
                ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Fifi")
            image?.isTemplate = false
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        let openPickerItem = NSMenuItem(title: "Open Picker", action: #selector(openPickerFromMenu), keyEquivalent: "")
        openPickerItem.target = self
        menu.addItem(openPickerItem)

        menu.addItem(.separator())

        let pauseRecordingItem = NSMenuItem(title: "Pause Recording", action: #selector(toggleRecordingPause), keyEquivalent: "")
        pauseRecordingItem.target = self
        menu.addItem(pauseRecordingItem)

        let clearHistoryItem = NSMenuItem(title: "Clear History…", action: #selector(clearHistoryFromMenu), keyEquivalent: "")
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

        let clearByTypeItem = NSMenuItem(title: "Clear by Type", action: nil, keyEquivalent: "")
        let clearByTypeMenu = NSMenu()
        for type in ClipItemType.allCases {
            let typeItem = NSMenuItem(title: type.fifiLabel, action: #selector(clearHistoryByType(_:)), keyEquivalent: "")
            typeItem.target = self
            typeItem.representedObject = type.rawValue
            clearByTypeMenu.addItem(typeItem)
        }
        clearByTypeItem.submenu = clearByTypeMenu
        menu.addItem(clearByTypeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Fifi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        // No permanent item.menu: a left click must reach statusItemClicked to
        // open the picker; the menu is attached transiently for right clicks.
        self.statusMenu = menu
        self.statusItem = item
        self.openPickerItem = openPickerItem
        self.pauseRecordingItem = pauseRecordingItem
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard let settings = settingsStore?.settings else { return }
        let display = KeyboardShortcutSpec(parsing: settings.hotkeyShortcut)?.display ?? settings.hotkeyShortcut
        openPickerItem?.title = "Open Picker    \(display)"
        pauseRecordingItem?.title = settings.isRecordingPaused ? "Resume Recording" : "Pause Recording"
        pauseRecordingItem?.state = settings.isRecordingPaused ? .on : .off
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isMenuClick = event.map { $0.type == .rightMouseUp || $0.modifierFlags.contains(.control) } ?? false
        if isMenuClick {
            showStatusMenu()
        } else {
            pickerController?.toggle()
        }
    }

    private func showStatusMenu() {
        guard let item = statusItem, let menu = statusMenu else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openPickerFromMenu() {
        pickerController?.toggle()
    }

    @objc private func toggleRecordingPause() {
        settingsStore?.update { settings in
            settings.isRecordingPaused.toggle()
        }
    }

    @objc private func clearHistoryFromMenu() {
        appState.clearHistoryKeepingPinned()
    }

    @objc private func clearHistoryByType(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let type = ClipItemType(rawValue: raw) else { return }
        appState.clearHistory(type: type)
    }

    /// Opens the SwiftUI Settings scene from AppKit by performing the
    /// app-menu "Settings…" item SwiftUI maintains (equivalent to ⌘,);
    /// falls back to the legacy responder-chain selector.
    @objc private func openSettingsFromMenu() {
        NSApp.activate(ignoringOtherApps: true)
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: {
               $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
           }) {
            appMenu.performActionForItem(at: index)
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        registerHotKeyIfNeeded(settings.hotkeyShortcut)
        applyLaunchAtLoginIfNeeded(settings)
        applyRecordingStateIfNeeded(settings)
        applyAppearanceIfNeeded(settings)
        applyEncryptionIfNeeded(settings)
        updateStatusMenu()
    }

    private func registerHotKeyIfNeeded(_ shortcut: String) {
        guard lastRegisteredShortcut != shortcut else { return }
        lastRegisteredShortcut = shortcut
        appState.hotkeyRegistrationMessage = nil
        hotKeyCenter.unregister()
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            appState.hotkeyRegistrationMessage = "Unsupported shortcut. Choose two modifiers and one letter or number."
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

    private func applyAppearanceIfNeeded(_ settings: AppSettings) {
        guard lastAppearance != settings.appearance else { return }
        lastAppearance = settings.appearance
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyEncryptionIfNeeded(_ settings: AppSettings) {
        guard lastEncryptBlobs != settings.privacy.encryptBlobs else { return }
        lastEncryptBlobs = settings.privacy.encryptBlobs
        guard let blobStore else { return }
        if settings.privacy.encryptBlobs {
            do {
                blobStore.setCipher(try EncryptionKeyStore.makeCipher())
                NSLog("Fifi blob encryption enabled")
            } catch {
                NSLog("Fifi failed to enable blob encryption: \(String(describing: error))")
            }
        } else {
            // New writes go out plaintext; already-encrypted blobs remain
            // readable because the key stays in the Keychain.
            blobStore.setCipher(nil)
        }
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
        // Sensitive auto-delete needs finer granularity than the 10-minute
        // cleanup; sweep expired entries every 20 s.
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.historyService?.deleteExpired() == true else { return }
                NotificationCenter.default.post(name: .fifiHistoryDidChange, object: nil)
            }
        }
    }
}

private struct FifiSettingsView: View {
    @ObservedObject var appState: FifiAppState

    var body: some View {
        SettingsScaffold {
            if let settingsStore = appState.settingsStore,
               let historyService = appState.historyService,
               let ignoreRulesStore = appState.ignoreRulesStore {
                GeneralSettingsPane(
                    settingsStore: settingsStore,
                    hotkeyRegistrationMessage: appState.hotkeyRegistrationMessage
                )
                PickerSettingsPane(settingsStore: settingsStore)
                PrivacySettingsPane(settingsStore: settingsStore, appState: appState)
                StorageSettingsPane(
                    settingsStore: settingsStore,
                    historyService: historyService,
                    appState: appState
                )
                IgnoreSettingsPane(
                    ignoreRulesStore: ignoreRulesStore,
                    appState: appState
                )
            } else {
                SettingsPane("General", systemImage: "gearshape") {
                    Section("Status") {
                        Text("Fifi is starting…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            AboutPane(
                tagline: "A fast, low-resource clipboard history manager for macOS.",
                copyright: "© 2026 Leafiy"
            )
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore
    let hotkeyRegistrationMessage: String?

    var body: some View {
        SettingsPane("General", systemImage: "gearshape", height: 320) {
            Section("Shortcut") {
                LabeledContent("Global shortcut") {
                    ShortcutField(spec: shortcutBinding)
                }
                shortcutCaption
            }
            Section("Behavior") {
                Picker("On selection", selection: selectionBehaviorBinding) {
                    Text("Paste immediately").tag(SelectionBehavior.paste)
                    Text("Copy only").tag(SelectionBehavior.copy)
                }
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }
            Section("Appearance") {
                Picker("Theme", selection: appearanceBinding) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
            }
        }
    }

    @ViewBuilder private var shortcutCaption: some View {
        if let hotkeyRegistrationMessage {
            Text(hotkeyRegistrationMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("Choose two modifier keys, then type one letter or number.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutBinding: Binding<KeyboardShortcutSpec> {
        Binding(
            get: {
                KeyboardShortcutSpec(parsing: settingsStore.settings.hotkeyShortcut)
                    ?? KeyboardShortcutSpec(parsing: AppSettings().hotkeyShortcut)!
            },
            set: { spec in
                settingsStore.update { settings in
                    settings.hotkeyShortcut = spec.shorthandDescription
                }
            }
        )
    }

    private var selectionBehaviorBinding: Binding<SelectionBehavior> {
        Binding(
            get: { settingsStore.settings.selectionBehavior },
            set: { newValue in
                settingsStore.update { settings in
                    settings.selectionBehavior = newValue
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.launchAtLogin },
            set: { newValue in
                settingsStore.update { settings in
                    settings.launchAtLogin = newValue
                }
            }
        )
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { settingsStore.settings.appearance },
            set: { newValue in
                settingsStore.update { settings in
                    settings.appearance = newValue
                }
            }
        )
    }
}

private struct StorageSettingsPane: View {
    private enum Metrics {
        static let numberFieldWidth: CGFloat = 88
    }

    @ObservedObject var settingsStore: SettingsStore
    let historyService: HistoryService
    @ObservedObject var appState: FifiAppState

    @State private var usageText = ""

    var body: some View {
        SettingsPane("Storage", systemImage: "internaldrive", height: 380) {
            Section("Limits") {
                storageLimitRow(
                    title: "Max history count",
                    value: intBinding(\.maxHistoryCount, upperBound: 100_000),
                    range: 0...100_000,
                    step: 100
                )
                storageLimitRow(
                    title: "Retention days",
                    value: intBinding(\.retentionDays, upperBound: 3_650),
                    range: 0...3_650,
                    step: 1
                )
                storageLimitRow(
                    title: "Max storage (MB)",
                    value: intBinding(\.maxStorageMB, upperBound: 100_000),
                    range: 0...100_000,
                    step: 64
                )
                Text("0 means unlimited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Usage") {
                LabeledContent("Current usage", value: usageText)
                LabeledContent("Actions") {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button("Refresh") {
                            refreshUsage()
                        }
                        Button("Clear History…") {
                            appState.clearHistoryKeepingPinned(refresh: refreshUsage)
                        }
                    }
                }
            }
            Section("Data") {
                LabeledContent("Settings") {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button("Export…") { appState.exportSettings() }
                        Button("Import…") { appState.importSettings() }
                    }
                }
                LabeledContent("History backup") {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button("Back Up…") { appState.backupHistory() }
                        Button("Restore…") { appState.restoreHistory() }
                    }
                }
                LabeledContent("Diagnostics") {
                    Button("Export…") { appState.exportDiagnostics() }
                }
                if let message = appState.dataActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: refreshUsage)
    }

    private func storageLimitRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: Metrics.numberFieldWidth)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>, upperBound: Int) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = min(Swift.max(newValue, 0), upperBound)
                }
            }
        )
    }

    private func refreshUsage() {
        let usage = historyService.usage()
        usageText = "\(usage.count) items · \(Self.formatMegabytes(usage.totalBytes))"
    }

    private static func formatMegabytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }
}

private struct IgnoreSettingsPane: View {
    @ObservedObject var appState: FifiAppState

    let ignoreRulesStore: IgnoreRulesStore

    @State private var ignoredApps: [IgnoredApp] = []
    @State private var regexRules: [IgnoreRegexRule] = []
    @State private var runningApps: [RunningAppChoice] = []
    @State private var bundleIDText = ""
    @State private var regexPatternText = ""
    @State private var regexLabelText = ""
    @State private var ignoredAppsMessage = ""
    @State private var regexMessage = ""

    init(ignoreRulesStore: IgnoreRulesStore, appState: FifiAppState) {
        self.ignoreRulesStore = ignoreRulesStore
        self.appState = appState
    }

    var body: some View {
        SettingsPane("Ignore", systemImage: "hand.raised") {
            Section("Ignored Apps") {
                if ignoredApps.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ignoredApps) { app in
                        ignoredAppRow(app)
                    }
                }
                TextField(
                    "Bundle identifier",
                    text: $bundleIDText,
                    prompt: Text("Bundle identifier, e.g. com.apple.Safari")
                )
                .labelsHidden()
                HStack(spacing: LeafiyDesign.Spacing.s) {
                    Menu("Running Apps") {
                        if runningApps.isEmpty {
                            Text("No running apps")
                        } else {
                            ForEach(runningApps) { app in
                                Button(app.name) {
                                    addIgnoredApp(bundleID: app.bundleID, appName: app.name)
                                }
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Add", action: addManualIgnoredApp)
                        .disabled(bundleIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !ignoredAppsMessage.isEmpty {
                    Text(ignoredAppsMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Ignored Text (Regex)") {
                if regexRules.isEmpty {
                    Text("No rules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(regexRules) { rule in
                        regexRuleRow(rule)
                    }
                }
                TextField(
                    "Pattern",
                    text: $regexPatternText,
                    prompt: Text("Regex pattern, e.g. ^secret-")
                )
                .labelsHidden()
                TextField(
                    "Label",
                    text: $regexLabelText,
                    prompt: Text("Label (optional)")
                )
                .labelsHidden()
                HStack {
                    Spacer()
                    Button("Add", action: addRegexRule)
                        .disabled(regexPatternText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !regexMessage.isEmpty {
                    Text(regexMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            reloadIgnoreData()
            refreshRunningApps()
        }
    }

    private func ignoredAppRow(_ app: IgnoredApp) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(app.appName?.isEmpty == false ? app.appName! : app.bundleID)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                removeIgnoredApp(bundleID: app.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func regexRuleRow(_ rule: IgnoreRegexRule) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { enabled in setRegexRule(id: rule.id, enabled: enabled) }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(rule.pattern)
                    .lineLimit(1)
                if let label = rule.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                removeRegexRule(id: rule.id)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func reloadIgnoreData() {
        do {
            ignoredApps = try ignoreRulesStore.ignoredApps()
            regexRules = try ignoreRulesStore.regexRules()
            ignoredAppsMessage = ""
            regexMessage = ""
        } catch {
            ignoredAppsMessage = "Couldn’t load ignore rules."
            NSLog("Failed to load ignore rules: \(String(describing: error))")
        }
    }

    private func refreshRunningApps() {
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else {
                return nil
            }
            return RunningAppChoice(name: app.localizedName ?? bundleID, bundleID: bundleID)
        }
        .filter { seen.insert($0.bundleID).inserted }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addManualIgnoredApp() {
        addIgnoredApp(bundleID: bundleIDText, appName: nil)
    }

    private func addIgnoredApp(bundleID: String, appName: String?) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try ignoreRulesStore.addIgnoredApp(bundleID: trimmed, appName: appName)
            bundleIDText = ""
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            ignoredAppsMessage = "Couldn’t add app."
            NSLog("Failed to add ignored app \(trimmed): \(String(describing: error))")
        }
    }

    private func removeIgnoredApp(bundleID: String) {
        do {
            try ignoreRulesStore.removeIgnoredApp(bundleID: bundleID)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            ignoredAppsMessage = "Couldn’t remove app."
            NSLog("Failed to remove ignored app \(bundleID): \(String(describing: error))")
        }
    }

    private func addRegexRule() {
        let pattern = regexPatternText.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = regexLabelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            _ = try ignoreRulesStore.addRegexRule(pattern: pattern, label: label.isEmpty ? nil : label)
            regexPatternText = ""
            regexLabelText = ""
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            regexMessage = "Invalid regex: \(error.localizedDescription)"
            NSLog("Failed to add regex rule: \(String(describing: error))")
        }
    }

    private func setRegexRule(id: Int64, enabled: Bool) {
        do {
            try ignoreRulesStore.setRegexRule(id: id, enabled: enabled)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            regexMessage = "Couldn’t update rule."
            NSLog("Failed to update regex rule \(id): \(String(describing: error))")
        }
    }

    private func removeRegexRule(id: Int64) {
        do {
            try ignoreRulesStore.removeRegexRule(id: id)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            regexMessage = "Couldn’t remove rule."
            NSLog("Failed to remove regex rule \(id): \(String(describing: error))")
        }
    }
}

private struct RunningAppChoice: Identifiable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
}
