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


    init() {
        LeafiyLocalization.language = SettingsStore.persistedAppLanguage()
        if CommandLine.arguments.contains("--leafiy-doctor") {
            let appBundle = LeafiyLocalization.moduleBundle(package: "Fifi", target: "Fifi")
            let leafiyUIBundle = LeafiyLocalization.moduleBundle(package: "LeafiyUI", target: "LeafiyUI")
            print(LeafiyDiagnostics.doctorReport(
                store: LeafiySettingsStore<AppSettings>.standard(directoryName: "Fifi"),
                probes: [
                    (label: "app", bundle: appBundle, key: "Search clipboard"),
                    (label: "leafiy-ui", bundle: leafiyUIBundle, key: "About")
                ]
            ))
            exit(0)
        }
        LeafiyDiagnostics.writeLaunchReport(
            store: LeafiySettingsStore<AppSettings>.standard(directoryName: "Fifi"),
            probes: [
                (label: "app",
                 bundle: LeafiyLocalization.moduleBundle(package: "Fifi", target: "Fifi"),
                 key: "Search clipboard"),
                (label: "leafiy-ui",
                 bundle: LeafiyLocalization.moduleBundle(package: "LeafiyUI", target: "LeafiyUI"),
                 key: "About")
            ]
        )
    }
    var body: some Scene {
        LeafiyMenuBarExtra {
            LeafiyFamilyMenu(language: appState.appLanguage) {
                FifiMenuContent(appState: appState)
            }
        } label: {
            FifiMenuBarIcon(isUploading: appState.isQuickShareUploading)
                .id(appState.appLanguage)
        }
        Settings {
            FifiSettingsView(appState: appState)
                .id(appState.appLanguage)
        }
        .commands {
            FifiCommands(appState: appState)
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
    @Published var appLanguage: AppLanguage = LeafiyLocalization.language
    @Published var dataActionMessage: String?
    @Published var isQuickShareUploading = false

    private var monitorReloadHandler: () -> Void = {}
    private var restoreHandler: (URL) -> Void = { _ in }
    private var openPickerHandler: () -> Void = {}
    private var toggleRecordingPauseHandler: () -> Void = {}
    private var togglePickerPreviewHandler: () -> Void = {}
    private var togglePickerFiltersHandler: () -> Void = {}
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
        self.appLanguage = settingsStore.appLanguage
        self.appPrivacyStore = appPrivacyStore
        self.supportDirectory = supportDirectory
        self.monitorReloadHandler = monitorReload
        self.restoreHandler = restoreHandler
    }

    func reloadMonitor() {
        monitorReloadHandler()
    }

    func bindMenuActions(
        openPicker: @escaping () -> Void,
        toggleRecordingPause: @escaping () -> Void,
        togglePickerPreview: @escaping () -> Void,
        togglePickerFilters: @escaping () -> Void
    ) {
        self.openPickerHandler = openPicker
        self.toggleRecordingPauseHandler = toggleRecordingPause
        self.togglePickerPreviewHandler = togglePickerPreview
        self.togglePickerFiltersHandler = togglePickerFilters
    }

    func openPicker() {
        openPickerHandler()
    }

    func toggleRecordingPause() {
        toggleRecordingPauseHandler()
    }

    func togglePickerPreview() {
        togglePickerPreviewHandler()
    }

    func togglePickerFilters() {
        togglePickerFiltersHandler()
    }

    func clearHistoryKeepingPinned(refresh: (() -> Void)? = nil) {
        guard confirmClearHistory() else { return }
        historyService?.clearAll(keepPinned: true)
        refresh?()
    }

    func clearHistory(type: ClipItemType) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: L("Clear all %@ items?"), type.fifiLabel)
        alert.informativeText = L("This cannot be undone.")
        alert.addButton(withTitle: L("Clear"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            historyService?.clear(type: type)
        }
    }

    private func confirmClearHistory() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Clear clipboard history?")
        alert.informativeText = L("Pinned items will be kept. This cannot be undone.")
        alert.addButton(withTitle: L("Clear"))
        alert.addButton(withTitle: L("Cancel"))
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
                settings: settingsStore.sanitizedSettings(),
                ignoredApps: (try? ignoreRulesStore.ignoredApps()) ?? [],
                ignoreRegexRules: (try? ignoreRulesStore.regexRules()) ?? [],
                appPrivacyRules: (try? appPrivacyStore?.rules() ?? []) ?? []
            )
            try SettingsCodec.encode(export).write(to: url)
            dataActionMessage = L("Settings exported.")
        } catch {
            dataActionMessage = String(format: L("Export failed: %@"), error.localizedDescription)
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
            settingsStore.replaceSettings(export.settings)
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
            dataActionMessage = L("Settings imported.")
        } catch {
            dataActionMessage = String(format: L("Import failed: %@"), error.localizedDescription)
        }
    }

    func backupHistory() {
        guard let historyService else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Back Up Here")
        panel.message = L("Choose a folder for the Fifi backup.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let folder = base.appendingPathComponent("Fifi Backup", isDirectory: true)
        do {
            try historyService.exportBackup(to: folder)
            dataActionMessage = String(format: L("Backed up to %@."), folder.path)
        } catch {
            dataActionMessage = String(format: L("Backup failed: %@"), error.localizedDescription)
        }
    }

    func restoreHistory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Restore")
        panel.message = L("Choose a Fifi backup folder. Fifi will relaunch.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Restore from backup?")
        alert.informativeText = L("This replaces all current history and relaunches Fifi.")
        alert.addButton(withTitle: L("Restore"))
        alert.addButton(withTitle: L("Cancel"))
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
            dataActionMessage = L("Diagnostics exported.")
        } catch {
            dataActionMessage = String(format: L("Diagnostics export failed: %@"), error.localizedDescription)
        }
    }
}

private struct FifiMenuBarIcon: View {
    let isUploading: Bool

    var body: some View {
        LeafiyMenuBarLabel(status: isUploading ? .busy : .idle)
    }
}

private struct FifiMenuContent: View {
    @ObservedObject var appState: FifiAppState

    private var settings: AppSettings? {
        appState.settingsStore?.settings
    }

    var body: some View {
        Button(L("Open Picker")) {
            appState.openPicker()
        }

        Divider()

        Button(settings?.showPreviewPanel == true ? L("Hide picker preview") : L("Show picker preview")) {
            appState.togglePickerPreview()
        }
        Button(settings?.showPickerFilters == true ? L("Hide filters in picker") : L("Show filters in picker")) {
            appState.togglePickerFilters()
        }

        Divider()

        Button(settings?.isRecordingPaused == true ? L("Resume Recording") : L("Pause Recording")) {
            appState.toggleRecordingPause()
        }
        Button(L("Clear History…")) {
            appState.clearHistoryKeepingPinned()
        }

        Menu(L("Clear by Type")) {
            ForEach(ClipItemType.allCases, id: \.rawValue) { type in
                Button(type.fifiLabel) {
                    appState.clearHistory(type: type)
                }
            }
        }

    }
}

private struct FifiCommands: Commands {
    @ObservedObject var appState: FifiAppState

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            if let shortcut = appState.settingsStore?.settings.hotkeyShortcut,
               let spec = KeyboardShortcutSpec(parsing: shortcut) {
                Divider()
                LeafiyShortcutMenuButton(
                    L("Open Picker"),
                    shortcut: spec,
                    action: appState.openPicker
                )
            }
        }
    }
}

@MainActor
final class AppDelegate: LeafiyAppDelegate {
    private var database: Database?
    private var historyStore: HistoryStore?
    private var blobStore: BlobStore?
    private var ignoreRulesStore: IgnoreRulesStore?
    private var appPrivacyStore: AppPrivacyStore?
    private var settingsStore: SettingsStore?
    private var historyService: HistoryService?
    private var monitor: ClipboardMonitor?
    private let hotKeyCenter = LeafiyHotKeyCenter(signature: "FIFI")
    private var pickerController: PickerController?

    private let appState = FifiAppState.shared
    private var cleanupTimer: Timer?
    private var expiryTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var quickShareStatusObserver: NSObjectProtocol?
    private var lastRegisteredShortcut: String?
    private var lastLaunchAtLogin: Bool?
    private var lastPauseState: Bool?
    private var warnedHotkeyConflict = false
    private var lastAppearance: AppearanceMode?
    private var activeQuickShareUploads = 0
    private enum HotKeyID {
        static let picker: UInt32 = 1
    }

    override func leafiyApplicationDidFinishLaunching(_ notification: Notification) {
        do {
            try configureServices()
        } catch {
            presentStartupFailure(error)
            return
        }

        observeQuickShareStatus()

        // The registration-failure callback must be wired before apply(settings:)
        // registers the hotkey, or a launch-time conflict has nowhere to report.
        hotKeyCenter.onRegisterFailed = { [weak self] shortcut in
            MainActor.assumeIsolated {
                self?.warnHotkeyConflict(shortcut: shortcut)
            }
        }

        observeSettings()
        if let settings = settingsStore?.settings {
            apply(settings: settings)
        }

        scheduleCleanup()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        pickerController?.show()
        return true
    }

    override func leafiyApplicationWillTerminate(_ notification: Notification) {
        cleanupTimer?.invalidate()
        expiryTimer?.invalidate()
        if let quickShareStatusObserver {
            NotificationCenter.default.removeObserver(quickShareStatusObserver)
        }
        monitor?.stop()
        hotKeyCenter.unregisterAll()
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
            settingsProvider: { settingsStore.sanitizedSettings() }
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
        appState.bindMenuActions(
            openPicker: { [weak pickerController] in pickerController?.toggle() },
            toggleRecordingPause: { [weak settingsStore] in
                settingsStore?.update { $0.isRecordingPaused.toggle() }
            },
            togglePickerPreview: { [weak settingsStore, weak pickerController] in
                settingsStore?.update { $0.showPreviewPanel.toggle() }
                pickerController?.resizeToSettings()
            },
            togglePickerFilters: { [weak settingsStore] in
                settingsStore?.update { $0.showPickerFilters.toggle() }
            }
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

        let restoreID = UUID().uuidString
        let staging = supportDirectory.appendingPathComponent(".fifi-restore-\(restoreID)", isDirectory: true)
        let rollback = supportDirectory.appendingPathComponent("fifi-pre-restore-\(restoreID)", isDirectory: true)
        let liveDB = supportDirectory.appendingPathComponent("fifi.sqlite3")
        var liveClosed = false

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try fileManager.copyItem(at: backupDB, to: staging.appendingPathComponent("fifi.sqlite3"))
            for name in ["blobs", "thumbnails"] {
                let source = folder.appendingPathComponent(name, isDirectory: true)
                let destination = staging.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: destination)
                } else {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
            }

            // Validate the copied database before closing the live app state.
            let stagedDatabase = try Database(path: staging.appendingPathComponent("fifi.sqlite3").path)
            let issues = try stagedDatabase.integrityCheck()
            stagedDatabase.close()
            guard issues.isEmpty else {
                throw RestoreError.invalidDatabase(issues.joined(separator: "; "))
            }
            for suffix in ["-wal", "-shm"] {
                try? fileManager.removeItem(at: URL(fileURLWithPath: staging.appendingPathComponent("fifi.sqlite3").path + suffix))
            }

            monitor?.stop()
            database?.close()
            liveClosed = true
            try fileManager.createDirectory(at: rollback, withIntermediateDirectories: true)

            try copyIfPresent(liveDB, to: rollback.appendingPathComponent("fifi.sqlite3"), fileManager: fileManager)
            for suffix in ["-wal", "-shm"] {
                try copyIfPresent(
                    URL(fileURLWithPath: liveDB.path + suffix),
                    to: rollback.appendingPathComponent("fifi.sqlite3" + suffix),
                    fileManager: fileManager
                )
            }
            for name in ["blobs", "thumbnails"] {
                try copyIfPresent(
                    supportDirectory.appendingPathComponent(name, isDirectory: true),
                    to: rollback.appendingPathComponent(name, isDirectory: true),
                    fileManager: fileManager
                )
                try? fileManager.removeItem(at: supportDirectory.appendingPathComponent(name, isDirectory: true))
            }
            for suffix in ["-wal", "-shm"] {
                try? fileManager.removeItem(at: URL(fileURLWithPath: liveDB.path + suffix))
            }
            try? fileManager.removeItem(at: liveDB)
            try fileManager.copyItem(at: staging.appendingPathComponent("fifi.sqlite3"), to: liveDB)
            for name in ["blobs", "thumbnails"] {
                try fileManager.copyItem(
                    at: staging.appendingPathComponent(name, isDirectory: true),
                    to: supportDirectory.appendingPathComponent(name, isDirectory: true)
                )
            }
            try? fileManager.removeItem(at: staging)
            relaunch()
        } catch {
            if liveClosed {
                do {
                    try restoreRollback(from: rollback, to: supportDirectory, liveDB: liveDB, fileManager: fileManager)
                    NSLog("Fifi restore failed; previous data was restored from the rollback copy")
                } catch {
                    NSLog("Fifi restore rollback also failed: %@", String(describing: error))
                }
            }
            NSLog("Fifi restore failed: %@", String(describing: error))
            try? fileManager.removeItem(at: staging)
            if liveClosed {
                NSApp.terminate(nil)
            }
        }
    }

    private enum RestoreError: LocalizedError {
        case invalidDatabase(String)

        var errorDescription: String? {
            switch self {
            case .invalidDatabase(let issues): return "backup database integrity check failed: \(issues)"
            }
        }
    }

    private func copyIfPresent(_ source: URL, to destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func restoreRollback(
        from rollback: URL,
        to supportDirectory: URL,
        liveDB: URL,
        fileManager: FileManager
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: liveDB.path + suffix))
        }
        for name in ["blobs", "thumbnails"] {
            try? fileManager.removeItem(at: supportDirectory.appendingPathComponent(name, isDirectory: true))
        }
        for suffix in ["", "-wal", "-shm"] {
            try copyIfPresent(
                URL(fileURLWithPath: rollback.appendingPathComponent("fifi.sqlite3").path + suffix),
                to: URL(fileURLWithPath: liveDB.path + suffix),
                fileManager: fileManager
            )
        }
        for name in ["blobs", "thumbnails"] {
            try copyIfPresent(
                rollback.appendingPathComponent(name, isDirectory: true),
                to: supportDirectory.appendingPathComponent(name, isDirectory: true),
                fileManager: fileManager
            )
        }
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
        alert.messageText = L("Fifi couldn’t start")
        alert.informativeText = String(format: L("The history database could not be opened. Fifi will quit.\n\n%@"), error.localizedDescription)
        alert.addButton(withTitle: L("Quit"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func warnHotkeyConflict(shortcut: KeyboardShortcutSpec) {
        let display = shortcut.display
        appState.hotkeyRegistrationMessage = String(format: L("Couldn’t register %@; another app may already own it."), display)
        guard !warnedHotkeyConflict else { return }
        warnedHotkeyConflict = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Picker shortcut unavailable")
        alert.informativeText = String(format: L("Fifi couldn’t register “%@” — another app probably owns it. You can still open the picker from the Fifi menu bar menu, or pick a different shortcut in Settings. This shortcut only opens the picker; copying with ⌘C is always recorded automatically."), display)
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    private func observeQuickShareStatus() {
        quickShareStatusObserver = NotificationCenter.default.addObserver(
            forName: .fifiQuickShareUploadStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                let isUploading = notification.userInfo?["isUploading"] as? Bool ?? false
                if isUploading {
                    self.activeQuickShareUploads += 1
                } else {
                    self.activeQuickShareUploads = max(0, self.activeQuickShareUploads - 1)
                }
                self.appState.isQuickShareUploading = self.activeQuickShareUploads > 0
            }
        }
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
        let language = AppLanguage(rawValue: settings.appLanguage) ?? .system
        LeafiyLocalization.language = language
        appState.appLanguage = language
        LeafiyApplicationPresentation.shared.apply(settings.applicationIconMode)
        registerHotKeyIfNeeded(settings.hotkeyShortcut)
        applyLaunchAtLoginIfNeeded(settings)
        applyRecordingStateIfNeeded(settings)
        applyAppearanceIfNeeded(settings)
    }

    private func registerHotKeyIfNeeded(_ shortcut: String) {
        guard lastRegisteredShortcut != shortcut else { return }
        lastRegisteredShortcut = shortcut
        appState.hotkeyRegistrationMessage = nil
        hotKeyCenter.unregister(id: HotKeyID.picker)
        guard let spec = KeyboardShortcutSpec(parsing: shortcut),
              LeafiyHotKeyCenter.isShortcutSupported(spec)
        else {
            appState.hotkeyRegistrationMessage = L("Unsupported shortcut. Choose two modifiers and one letter or number.")
            NSLog("Unsupported hotkey shortcut: \(shortcut)")
            return
        }
        hotKeyCenter.register(id: HotKeyID.picker, shortcut: spec) { [weak self] in
            // Called synchronously from the Carbon handler on the main thread;
            // stay synchronous so activation keeps its user-event context.
            MainActor.assumeIsolated {
                self?.pickerController?.toggle()
            }
        }
    }

    private func applyLaunchAtLoginIfNeeded(_ settings: AppSettings) {
        guard lastLaunchAtLogin != settings.launchAtLogin else { return }
        lastLaunchAtLogin = settings.launchAtLogin
        LeafiyLaunchAtLogin.setEnabled(settings.launchAtLogin)
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
        LeafiyFamilySettings(language: appState.appLanguage) {
            if let settingsStore = appState.settingsStore,
               let historyService = appState.historyService,
               let ignoreRulesStore = appState.ignoreRulesStore {
                GeneralSettingsPane(
                    settingsStore: settingsStore,
                    hotkeyRegistrationMessage: appState.hotkeyRegistrationMessage
                )
                PickerSettingsPane(settingsStore: settingsStore)
                ShareSettingsPane(settingsStore: settingsStore)
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
                SettingsPane(L("General"), systemImage: "gearshape") {
                    Section(L("Status")) {
                        Text(L("Fifi is starting…"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore
    let hotkeyRegistrationMessage: String?

    var body: some View {
        LeafiyGeneralPane(
            language: appLanguageBinding,
            launchAtLogin: launchAtLoginBinding,
            applicationIconMode: applicationIconModeBinding
        ) {
            LabeledContent(L("Global shortcut")) {
                ShortcutField(spec: shortcutBinding)
            }
            shortcutCaption
        } tail: {
            Picker(L("On selection"), selection: selectionBehaviorBinding) {
                Text(L("Paste immediately")).tag(SelectionBehavior.paste)
                Text(L("Copy only")).tag(SelectionBehavior.copy)
            }
            Picker(L("Theme"), selection: appearanceBinding) {
                Text(L("System")).tag(AppearanceMode.system)
                Text(L("Light")).tag(AppearanceMode.light)
                Text(L("Dark")).tag(AppearanceMode.dark)
            }
        }
    }

    @ViewBuilder private var shortcutCaption: some View {
        if let hotkeyRegistrationMessage {
            Text(hotkeyRegistrationMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text(L("Choose two modifier keys, then type one letter or number."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { settingsStore.appLanguage },
            set: { newValue in
                settingsStore.appLanguage = newValue
            }
        )
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

    private var applicationIconModeBinding: Binding<LeafiyApplicationIconMode> {
        Binding(
            get: { settingsStore.settings.applicationIconMode },
            set: { newValue in
                settingsStore.update { settings in
                    settings.applicationIconMode = newValue
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
        SettingsPane(L("Storage"), systemImage: "internaldrive", height: 400) {
            Section(L("Limits")) {
                storageLimitRow(
                    title: L("Max history count"),
                    value: intBinding(\.maxHistoryCount, upperBound: 100_000),
                    range: 0...100_000,
                    step: 100
                )
                storageLimitRow(
                    title: L("Retention days"),
                    value: intBinding(\.retentionDays, upperBound: 3_650),
                    range: 0...3_650,
                    step: 1
                )
                storageLimitRow(
                    title: L("Max storage (MB)"),
                    value: intBinding(\.maxStorageMB, upperBound: 100_000),
                    range: 0...100_000,
                    step: 64
                )
                Text(L("0 means unlimited."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("Favorites are kept when clearing history and are exempt from automatic cleanup limits."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Usage")) {
                LabeledContent(L("Current usage"), value: usageText)
                LabeledContent(L("Actions")) {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button(L("Refresh")) {
                            refreshUsage()
                        }
                        Button(L("Clear History…")) {
                            appState.clearHistoryKeepingPinned(refresh: refreshUsage)
                        }
                    }
                }
            }
            Section(L("Data")) {
                LabeledContent(L("Settings")) {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button(L("Export…")) { appState.exportSettings() }
                        Button(L("Import…")) { appState.importSettings() }
                    }
                }
                LabeledContent(L("History backup")) {
                    HStack(spacing: LeafiyDesign.Spacing.s) {
                        Button(L("Back Up…")) { appState.backupHistory() }
                        Button(L("Restore…")) { appState.restoreHistory() }
                    }
                }
                LabeledContent(L("Diagnostics")) {
                    Button(L("Export…")) { appState.exportDiagnostics() }
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
        usageText = String(format: L("%1$d items · %2$@"), usage.count, Self.formatMegabytes(usage.totalBytes))
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
        SettingsPane(L("Ignore"), systemImage: "hand.raised") {
            Section(L("Ignored Apps")) {
                if ignoredApps.isEmpty {
                    Text(L("No ignored apps"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ignoredApps) { app in
                        ignoredAppRow(app)
                    }
                }
                TextField(
                    L("Bundle identifier"),
                    text: $bundleIDText,
                    prompt: Text(L("Bundle identifier, e.g. com.apple.Safari"))
                )
                .labelsHidden()
                HStack(spacing: LeafiyDesign.Spacing.s) {
                    Menu(L("Running Apps")) {
                        if runningApps.isEmpty {
                            Text(L("No running apps"))
                        } else {
                            ForEach(runningApps) { app in
                                Button {
                                    addIgnoredApp(bundleID: app.bundleID, appName: app.name)
                                } label: {
                                    Text(verbatim: app.name)
                                }
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button(L("Add"), action: addManualIgnoredApp)
                        .disabled(bundleIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !ignoredAppsMessage.isEmpty {
                    Text(ignoredAppsMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section(L("Ignored Text (Regex)")) {
                if regexRules.isEmpty {
                    Text(L("No rules"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(regexRules) { rule in
                        regexRuleRow(rule)
                    }
                }
                TextField(
                    L("Pattern"),
                    text: $regexPatternText,
                    prompt: Text(L("Regex pattern, e.g. ^secret-"))
                )
                .labelsHidden()
                TextField(
                    L("Label"),
                    text: $regexLabelText,
                    prompt: Text(L("Label (optional)"))
                )
                .labelsHidden()
                HStack {
                    Spacer()
                    Button(L("Add"), action: addRegexRule)
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
                Text(verbatim: app.appName?.isEmpty == false ? app.appName! : app.bundleID)
                    .lineLimit(1)
                Text(verbatim: app.bundleID)
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
            .help(L("Remove"))
        }
    }

    private func regexRuleRow(_ rule: IgnoreRegexRule) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Toggle(isOn: Binding(
                get: { rule.enabled },
                set: { enabled in setRegexRule(id: rule.id, enabled: enabled) }
            )) {
                EmptyView()
            }
            .labelsHidden()
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(verbatim: rule.pattern)
                    .lineLimit(1)
                if let label = rule.label, !label.isEmpty {
                    Text(verbatim: label)
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
            .help(L("Remove"))
        }
    }

    private func reloadIgnoreData() {
        do {
            ignoredApps = try ignoreRulesStore.ignoredApps()
            regexRules = try ignoreRulesStore.regexRules()
            ignoredAppsMessage = ""
            regexMessage = ""
        } catch {
            ignoredAppsMessage = L("Couldn’t load ignore rules.")
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
            ignoredAppsMessage = L("Couldn’t add app.")
            NSLog("Failed to add ignored app \(trimmed): \(String(describing: error))")
        }
    }

    private func removeIgnoredApp(bundleID: String) {
        do {
            try ignoreRulesStore.removeIgnoredApp(bundleID: bundleID)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            ignoredAppsMessage = L("Couldn’t remove app.")
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
            regexMessage = String(format: L("Invalid regex: %@"), error.localizedDescription)
            NSLog("Failed to add regex rule: \(String(describing: error))")
        }
    }

    private func setRegexRule(id: Int64, enabled: Bool) {
        do {
            try ignoreRulesStore.setRegexRule(id: id, enabled: enabled)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            regexMessage = L("Couldn’t update rule.")
            NSLog("Failed to update regex rule \(id): \(String(describing: error))")
        }
    }

    private func removeRegexRule(id: Int64) {
        do {
            try ignoreRulesStore.removeRegexRule(id: id)
            reloadIgnoreData()
            appState.reloadMonitor()
        } catch {
            regexMessage = L("Couldn’t remove rule.")
            NSLog("Failed to remove regex rule \(id): \(String(describing: error))")
        }
    }
}

private struct RunningAppChoice: Identifiable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
}
