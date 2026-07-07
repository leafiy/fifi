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
            case .general: return NSSize(width: 560, height: 330)
            case .storage: return NSSize(width: 560, height: 344)
            case .ignore: return NSSize(width: 560, height: 376)
            }
        }
    }

    private let historyService: HistoryService
    private let ignoreRulesStore: IgnoreRulesStore
    private let monitorReload: () -> Void
    private let onPaneChanged: (Pane) -> Void

    @State private var selectedPane: Pane = .general
    @State private var firstHotkeyModifier: HotkeyModifier = .command
    @State private var secondHotkeyModifier: HotkeyModifier = .shift
    @State private var hotkeyKey = "V"
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
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)

            selectedTab
                .padding(.top, 48)

            Picker("", selection: $selectedPane) {
                ForEach(Pane.allCases, id: \.self) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 264)
            .padding(.top, -18)
        }
        .padding(SettingsMetrics.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadHotkeyEditor(from: settingsStore.settings.hotkeyShortcut)
            refreshUsage()
            reloadIgnoreData()
            refreshRunningApps()
            onPaneChanged(selectedPane)
        }
        .onChange(of: selectedPane) { pane in
            onPaneChanged(pane)
        }
    }

    @ViewBuilder private var selectedTab: some View {
        switch selectedPane {
        case .general:
            generalTab
        case .storage:
            storageTab
        case .ignore:
            ignoreTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        SettingsPane {
            SettingsSection("Shortcut") {
                SettingsRow("Global shortcut") {
                    Picker("", selection: $firstHotkeyModifier) {
                        ForEach(HotkeyModifier.allCases) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 104)

                    Picker("", selection: $secondHotkeyModifier) {
                        ForEach(HotkeyModifier.allCases) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 104)

                    TextField("V", text: $hotkeyKey)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                }
                .onChange(of: firstHotkeyModifier) { _ in commitHotkeyEditor() }
                .onChange(of: secondHotkeyModifier) { _ in commitHotkeyEditor() }
                .onChange(of: hotkeyKey) { _ in commitHotkeyEditor() }
                SettingsFootnote(hotkeyError ?? "Choose two modifier keys, then type one letter or number.")
                    .foregroundStyle(hotkeyError == nil ? Color.secondary : Color.red)
            }

            SettingsSection("Behavior") {
                SettingsRow("On selection") {
                    Picker("", selection: settingBinding(\.selectionBehavior)) {
                        Text("Paste immediately").tag(SelectionBehavior.paste)
                        Text("Copy only").tag(SelectionBehavior.copy)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                SettingsRow("Launch at login") {
                    Toggle("", isOn: settingBinding(\.launchAtLogin))
                        .labelsHidden()
                }
            }
        }
    }

    private func commitHotkeyEditor() {
        let normalizedKey = normalizeHotkeyKey(hotkeyKey)
        if hotkeyKey != normalizedKey {
            hotkeyKey = normalizedKey
        }
        guard firstHotkeyModifier != secondHotkeyModifier else {
            hotkeyError = "Choose two different modifier keys."
            return
        }
        guard !normalizedKey.isEmpty else {
            hotkeyError = "Type one letter or number for the shortcut key."
            return
        }
        let shortcut = "\(firstHotkeyModifier.token)+\(secondHotkeyModifier.token)+\(normalizedKey.lowercased())"
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            hotkeyError = "Unsupported shortcut."
            return
        }
        hotkeyError = nil
        settingsStore.update { settings in
            settings.hotkeyShortcut = shortcut
        }
    }

    private func loadHotkeyEditor(from shortcut: String) {
        let parsed = parseHotkeyShortcut(shortcut)
            ?? parseHotkeyShortcut(AppSettings().hotkeyShortcut)
            ?? (.command, .shift, "V")
        firstHotkeyModifier = parsed.first
        secondHotkeyModifier = parsed.second
        hotkeyKey = parsed.key
        hotkeyError = nil
    }

    private func parseHotkeyShortcut(_ shortcut: String) -> (first: HotkeyModifier, second: HotkeyModifier, key: String)? {
        let tokens = shortcut
            .replacingOccurrences(of: "⌘", with: "cmd+")
            .replacingOccurrences(of: "⇧", with: "shift+")
            .replacingOccurrences(of: "⌥", with: "option+")
            .replacingOccurrences(of: "⌃", with: "control+")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard tokens.count >= 3 else { return nil }

        let modifiers = tokens.dropLast().compactMap(HotkeyModifier.init(token:))
        let uniqueModifiers = modifiers.reduce(into: [HotkeyModifier]()) { result, modifier in
            if !result.contains(modifier) {
                result.append(modifier)
            }
        }
        let key = normalizeHotkeyKey(String(tokens.last ?? ""))
        guard uniqueModifiers.count >= 2, !key.isEmpty else { return nil }
        return (uniqueModifiers[0], uniqueModifiers[1], key)
    }

    private func normalizeHotkeyKey(_ rawValue: String) -> String {
        let allowedCharacters = rawValue.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowedCharacters.prefix(1))
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
                SettingsRow("Actions") {
                    Button("Refresh", action: refreshUsage)
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
                SettingsRow("Apps") {
                    if ignoredApps.isEmpty {
                        Text("No ignored apps")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                SettingsRow("Add app") {
                    TextField("Bundle identifier", text: $bundleIDToAdd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 206)
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
                    SettingsFootnote(ignoreAppsError)
                        .foregroundStyle(Color.red)
                }
            }

            SettingsSection("Ignored Text (Regex)") {
                SettingsRow("Rules") {
                    if regexRules.isEmpty {
                        Text("No rules")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                SettingsRow("Add rule") {
                    TextField("Pattern", text: $regexPatternToAdd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    TextField("Label (optional)", text: $regexLabelToAdd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Button("Add", action: addRegexRule)
                        .disabled(regexPatternToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let regexError {
                    SettingsFootnote(regexError)
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
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                content
            }
            .padding(.horizontal, SettingsMetrics.outerPadding)
            .padding(.top, 0)
            .padding(.bottom, SettingsMetrics.outerPadding)
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
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
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
        HStack(alignment: .top, spacing: SettingsMetrics.rowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: SettingsMetrics.labelWidth, alignment: .trailing)
                .padding(.top, 3)
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
            .padding(.leading, SettingsMetrics.contentIndent)
    }
}

private enum SettingsMetrics {
    static let windowPadding: CGFloat = 12
    static let outerPadding: CGFloat = 16
    static let labelWidth: CGFloat = 116
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let contentIndent: CGFloat = labelWidth + rowSpacing
}

private enum HotkeyModifier: String, CaseIterable, Identifiable {
    case command
    case shift
    case option
    case control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "Command"
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        }
    }

    var token: String {
        switch self {
        case .command: return "cmd"
        case .shift: return "shift"
        case .option: return "option"
        case .control: return "control"
        }
    }

    init?(token: String) {
        switch token {
        case "cmd", "command":
            self = .command
        case "shift":
            self = .shift
        case "option", "alt":
            self = .option
        case "ctrl", "control":
            self = .control
        default:
            return nil
        }
    }
}

private struct RunningAppChoice: Identifiable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}
