import AppKit
import Foundation
import SwiftUI
import FifiCore

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    enum Pane: String, CaseIterable, Hashable {
        case general
        case storage
        case ignore

        var title: String {
            switch self {
            case .general: return "General"
            case .storage: return "Storage"
            case .ignore: return "Ignore"
            }
        }

        var windowSize: NSSize {
            switch self {
            case .general: return NSSize(width: 520, height: 244)
            case .storage: return NSSize(width: 520, height: 286)
            case .ignore: return NSSize(width: 660, height: 520)
            }
        }
    }

    private let historyService: HistoryService
    private let ignoreRulesStore: IgnoreRulesStore
    private let monitorReload: () -> Void
    private let onPaneChanged: (Pane) -> Void

    @State private var selectedPane: Pane = .general
    @State private var hotkeyDraft = ""
    @State private var hotkeyError: String?
    @State private var usageCount = 0
    @State private var usageBytes = 0
    @State private var showingClearConfirmation = false

    @State private var ignoredApps: [IgnoredApp] = []
    @State private var runningApps: [RunningAppChoice] = []
    @State private var bundleIDToAdd = ""
    @State private var ignoreAppsError: String?

    @State private var regexRules: [IgnoreRegexRule] = []
    @State private var regexPatternToAdd = ""
    @State private var regexLabelToAdd = ""
    @State private var regexError: String?

    init(
        historyService: HistoryService,
        ignoreRulesStore: IgnoreRulesStore,
        monitorReload: @escaping () -> Void,
        onPaneChanged: @escaping (Pane) -> Void = { _ in }
    ) {
        self.historyService = historyService
        self.ignoreRulesStore = ignoreRulesStore
        self.monitorReload = monitorReload
        self.onPaneChanged = onPaneChanged
    }

    var body: some View {
        TabView(selection: $selectedPane) {
            generalTab
                .tabItem { Text(Pane.general.title) }
                .tag(Pane.general)
            storageTab
                .tabItem { Text(Pane.storage.title) }
                .tag(Pane.storage)
            ignoreTab
                .tabItem { Text(Pane.ignore.title) }
                .tag(Pane.ignore)
        }
        .onAppear {
            hotkeyDraft = settingsStore.settings.hotkeyShortcut
            refreshUsage()
            reloadIgnoreData()
            refreshRunningApps()
            onPaneChanged(selectedPane)
        }
        .onChange(of: selectedPane) { pane in
            onPaneChanged(pane)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        SettingsPane {
            SettingsSection("Shortcut") {
                SettingsRow("Global shortcut") {
                    TextField("cmd+shift+v", text: $hotkeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit(commitHotkey)
                }
                SettingsFootnote(hotkeyError ?? "Press Return to save. Use cmd, shift, option, or ctrl with a key.")
                    .foregroundStyle(hotkeyError == nil ? Color.secondary : Color.red)
            }

            SettingsSection("Behavior") {
                SettingsRow("On selection") {
                    Picker("", selection: settingBinding(\.selectionBehavior)) {
                        Text("Paste immediately").tag(SelectionBehavior.paste)
                        Text("Copy only").tag(SelectionBehavior.copy)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                SettingsRow("Launch at login") {
                    Toggle("", isOn: settingBinding(\.launchAtLogin))
                        .labelsHidden()
                }
            }
        }
    }

    private func commitHotkey() {
        let normalized = hotkeyDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard HotKeyCenter.isShortcutSupported(normalized) else {
            hotkeyError = "Unsupported shortcut. Include cmd, option, ctrl, or shift plus a key."
            return
        }
        hotkeyDraft = normalized
        hotkeyError = nil
        settingsStore.update { settings in
            settings.hotkeyShortcut = normalized
        }
    }

    // MARK: - Storage

    private var storageTab: some View {
        SettingsPane {
            SettingsSection("Limits") {
                limitRow("Max history count", keyPath: \.maxHistoryCount, range: 0...100_000, step: 100)
                limitRow("Retention days", keyPath: \.retentionDays, range: 0...3_650, step: 1)
                limitRow("Max storage (MB)", keyPath: \.maxStorageMB, range: 0...100_000, step: 64)
                SettingsFootnote("0 means unlimited.")
            }

            SettingsSection("Usage") {
                SettingsRow("Current usage") {
                    Text("\(usageCount) items · \(formatMegabytes(usageBytes))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Refresh", action: refreshUsage)
                    Spacer()
                    Button("Clear History…", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .alert("Clear clipboard history?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                historyService.clearAll(keepPinned: true)
                refreshUsage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items will be kept. This cannot be undone.")
        }
    }

    private func limitRow(
        _ title: String,
        keyPath: WritableKeyPath<AppSettings, Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        SettingsRow(title) {
            TextField("0", value: settingBinding(keyPath), formatter: Self.integerFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
            Stepper("", value: settingBinding(keyPath), in: range, step: step)
                .labelsHidden()
        }
    }

    private func refreshUsage() {
        let usage = historyService.usage()
        usageCount = usage.count
        usageBytes = usage.totalBytes
    }

    // MARK: - Ignore

    private var ignoreTab: some View {
        SettingsPane {
            SettingsSection("Ignored Apps") {
                if ignoredApps.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(ignoredApps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.appName?.isEmpty == false ? app.appName! : app.bundleID)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            removeIgnoredApp(app)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $bundleIDToAdd)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addIgnoredApp(bundleID: bundleIDToAdd, appName: nil)
                    }
                    .disabled(bundleIDToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Menu("Running Apps") {
                        ForEach(runningApps) { app in
                            Button("\(app.name) (\(app.bundleID))") {
                                addIgnoredApp(bundleID: app.bundleID, appName: app.name)
                            }
                        }
                    }
                    .fixedSize()
                }
                if let ignoreAppsError {
                    Text(ignoreAppsError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            }

            SettingsSection("Ignored Text (Regex)") {
                if regexRules.isEmpty {
                    Text("No rules")
                        .foregroundStyle(.secondary)
                }
                ForEach(regexRules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { regexRules.first(where: { $0.id == rule.id })?.enabled ?? rule.enabled },
                            set: { enabled in setRegexRule(rule, enabled: enabled) }
                        ))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.pattern)
                                .lineLimit(1)
                            if let label = rule.label, !label.isEmpty {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            removeRegexRule(rule)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Pattern", text: $regexPatternToAdd)
                        .textFieldStyle(.roundedBorder)
                    TextField("Label (optional)", text: $regexLabelToAdd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button("Add", action: addRegexRule)
                        .disabled(regexPatternToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let regexError {
                    Text(regexError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private func reloadIgnoreData() {
        do {
            ignoredApps = try ignoreRulesStore.ignoredApps()
            regexRules = try ignoreRulesStore.regexRules()
            ignoreAppsError = nil
        } catch {
            ignoreAppsError = "Couldn’t load ignore rules."
            NSLog("Failed to load ignore rules: \(String(describing: error))")
        }
    }

    private func addIgnoredApp(bundleID: String, appName: String?) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let name = appName ?? runningApps.first(where: { $0.bundleID == trimmed })?.name
            try ignoreRulesStore.addIgnoredApp(bundleID: trimmed, appName: name)
            bundleIDToAdd = ""
            ignoreAppsError = nil
            reloadIgnoreData()
            monitorReload()
        } catch {
            ignoreAppsError = "Couldn’t add app."
            NSLog("Failed to add ignored app \(trimmed): \(String(describing: error))")
        }
    }

    private func removeIgnoredApp(_ app: IgnoredApp) {
        do {
            try ignoreRulesStore.removeIgnoredApp(bundleID: app.bundleID)
            reloadIgnoreData()
            monitorReload()
        } catch {
            ignoreAppsError = "Couldn’t remove app."
            NSLog("Failed to remove ignored app \(app.bundleID): \(String(describing: error))")
        }
    }

    private func addRegexRule() {
        let pattern = regexPatternToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = regexLabelToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            _ = try ignoreRulesStore.addRegexRule(pattern: pattern, label: label.isEmpty ? nil : label)
            regexPatternToAdd = ""
            regexLabelToAdd = ""
            regexError = nil
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexError = "Invalid regex: \(error.localizedDescription)"
            NSLog("Failed to add regex rule: \(String(describing: error))")
        }
    }

    private func setRegexRule(_ rule: IgnoreRegexRule, enabled: Bool) {
        do {
            try ignoreRulesStore.setRegexRule(id: rule.id, enabled: enabled)
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexError = "Couldn’t update rule."
            NSLog("Failed to update regex rule \(rule.id): \(String(describing: error))")
        }
    }

    private func removeRegexRule(_ rule: IgnoreRegexRule) {
        do {
            try ignoreRulesStore.removeRegexRule(id: rule.id)
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexError = "Couldn’t remove rule."
            NSLog("Failed to remove regex rule \(rule.id): \(String(describing: error))")
        }
    }

    private func refreshRunningApps() {
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else {
                return nil
            }
            let name = app.localizedName ?? bundleID
            return RunningAppChoice(name: name, bundleID: bundleID)
        }
        .filter { seen.insert($0.bundleID).inserted }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func formatMegabytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 1_000_000
        return formatter
    }()
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSection<Content: View>: View {
    private let title: String
    @ViewBuilder private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    private let title: String
    @ViewBuilder private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)
            HStack(spacing: 8) {
                content
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

private struct SettingsFootnote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 144)
    }
}

private struct RunningAppChoice: Identifiable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}
