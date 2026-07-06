import AppKit
import Foundation
import SwiftUI
import FifiCore

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private let historyService: HistoryService
    private let ignoreRulesStore: IgnoreRulesStore
    private let monitorReload: () -> Void

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
        monitorReload: @escaping () -> Void
    ) {
        self.historyService = historyService
        self.ignoreRulesStore = ignoreRulesStore
        self.monitorReload = monitorReload
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Text("General") }
            storageTab
                .tabItem { Text("Storage") }
            ignoreTab
                .tabItem { Text("Ignore") }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 440)
        .onAppear {
            hotkeyDraft = settingsStore.settings.hotkeyShortcut
            refreshUsage()
            reloadIgnoreData()
            refreshRunningApps()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                TextField("cmd+shift+v", text: $hotkeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitHotkey)
                Text(hotkeyError ?? "Press Return to save. Use tokens like cmd+shift+v.")
                    .font(.caption)
                    .foregroundStyle(hotkeyError == nil ? Color.secondary : Color.red)
            }

            Picker("Selection", selection: settingBinding(\.selectionBehavior)) {
                Text("Paste immediately").tag(SelectionBehavior.paste)
                Text("Copy only").tag(SelectionBehavior.copy)
            }
            .pickerStyle(.radioGroup)

            Toggle("Launch at login", isOn: settingBinding(\.launchAtLogin))

            Stepper(
                "Polling interval: \(settingsStore.settings.pollingIntervalMS) ms",
                value: settingBinding(\.pollingIntervalMS),
                in: 50...1000,
                step: 50
            )
        }
        .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 14) {
            intSettingRow(
                "Max history count",
                keyPath: \.maxHistoryCount,
                range: 0...100_000,
                step: 100,
                unlimitedHint: "0 = unlimited"
            )
            intSettingRow(
                "Retention days",
                keyPath: \.retentionDays,
                range: 0...3_650,
                step: 1,
                unlimitedHint: "0 = unlimited"
            )
            intSettingRow(
                "Max storage MB",
                keyPath: \.maxStorageMB,
                range: 0...100_000,
                step: 64,
                unlimitedHint: "0 = unlimited"
            )

            Divider()

            HStack {
                Text("Current usage")
                Spacer()
                Text("\(usageCount) items · \(formatMegabytes(usageBytes))")
                    .foregroundStyle(.secondary)
                Button("Refresh", action: refreshUsage)
            }

            Button("Clear History…") {
                showingClearConfirmation = true
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

            Spacer()
        }
        .padding(.top, 12)
    }

    private func intSettingRow(
        _ title: String,
        keyPath: WritableKeyPath<AppSettings, Int>,
        range: ClosedRange<Int>,
        step: Int,
        unlimitedHint: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let unlimitedHint {
                    Text(unlimitedHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("0", value: settingBinding(keyPath), formatter: Self.integerFormatter)
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
        VStack(alignment: .leading, spacing: 12) {
            ignoredAppsSection
            Divider()
            regexRulesSection
        }
        .padding(.top, 8)
    }

    private var ignoredAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ignored Apps")
                .font(.headline)

            List(ignoredApps) { app in
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
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(height: 90)

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
                Button("Refresh") {
                    refreshRunningApps()
                }
            }
            if let ignoreAppsError {
                Text(ignoreAppsError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var regexRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Regex Rules")
                .font(.headline)

            List(regexRules) { rule in
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
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(height: 90)

            HStack {
                TextField("Pattern", text: $regexPatternToAdd)
                    .textFieldStyle(.roundedBorder)
                TextField("Label", text: $regexLabelToAdd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button("Add", action: addRegexRule)
                    .disabled(regexPatternToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let regexError {
                Text(regexError)
                    .font(.caption)
                    .foregroundStyle(.red)
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

private struct RunningAppChoice: Identifiable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}
