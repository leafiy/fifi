import AppKit
import FifiCore
import LeafiyUI
import SwiftUI

struct PickerSettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsPane("Picker", systemImage: "rectangle.and.text.magnifyingglass", height: 360) {
            Section("Layout") {
                stepperRow("Width", binding: intBinding(\.pickerWidth, lower: 320, upper: 900), range: 320...900, step: 20)
                stepperRow("Height", binding: intBinding(\.pickerHeight, lower: 320, upper: 1000), range: 320...1000, step: 20)
                Picker("Row density", selection: densityBinding) {
                    Text("Comfortable").tag(RowDensity.comfortable)
                    Text("Compact").tag(RowDensity.compact)
                }
                Toggle("Show preview panel", isOn: boolBinding(\.showPreviewPanel))
            }
            Section("Search") {
                Picker("Sort order", selection: sortBinding) {
                    Text("Most recent").tag(HistorySortOrder.recency)
                    Text("Most used").tag(HistorySortOrder.mostUsed)
                }
                Toggle("Fuzzy ranking", isOn: boolBinding(\.fuzzyRanking))
                Toggle("Number shortcuts (⌘1–0)", isOn: boolBinding(\.numberShortcuts))
            }
        }
    }

    private func stepperRow(_ title: String, binding: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Text(title)
            Spacer()
            TextField(title, value: binding, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Stepper(title, value: binding, in: range, step: step)
                .labelsHidden()
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>, lower: Int, upper: Int) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { $0[keyPath: keyPath] = min(max(newValue, lower), upper) }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in settingsStore.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var densityBinding: Binding<RowDensity> {
        Binding(
            get: { settingsStore.settings.rowDensity },
            set: { newValue in settingsStore.update { $0.rowDensity = newValue } }
        )
    }

    private var sortBinding: Binding<HistorySortOrder> {
        Binding(
            get: { settingsStore.settings.sortOrder },
            set: { newValue in settingsStore.update { $0.sortOrder = newValue } }
        )
    }
}

struct PrivacySettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var appState: FifiAppState

    @State private var rules: [AppPrivacyRule] = []
    @State private var bundleIDText = ""
    @State private var newMode: AppPrivacyMode = .sensitive
    @State private var message = ""

    var body: some View {
        SettingsPane("Privacy", systemImage: "hand.raised.square", height: 520) {
            Section("Detection") {
                Toggle("Skip password-manager items", isOn: privacyBool(\.skipConcealed))
                Toggle("Detect credit card numbers", isOn: privacyBool(\.detectCreditCards))
                Toggle("Detect API keys and tokens", isOn: privacyBool(\.detectAPIKeys))
                Toggle("Detect verification codes", isOn: privacyBool(\.detectVerificationCodes))
            }
            Section("Sensitive handling") {
                Picker("When detected", selection: handlingBinding) {
                    Text("Don't record").tag(SensitiveHandling.ignore)
                    Text("Auto-delete after delay").tag(SensitiveHandling.autoDelete)
                }
                if settingsStore.settings.privacy.handling == .autoDelete {
                    HStack {
                        Text("Delete after (seconds)")
                        Spacer()
                        TextField("Seconds", value: autoDeleteBinding, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Stepper("Seconds", value: autoDeleteBinding, in: 5...3600, step: 5)
                            .labelsHidden()
                    }
                }
            }
            Section("Modes") {
                Toggle("Private mode (memory only)", isOn: privacyBool(\.privateMode))
                Toggle("Encrypt stored images and large text", isOn: privacyBool(\.encryptBlobs))
                Text("Private mode keeps captures in memory and never writes them to disk. Encryption protects blob files at rest; search text stays indexed for speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Per-App Privacy") {
                if rules.isEmpty {
                    Text("No per-app rules")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }
                }
                TextField("Bundle identifier", text: $bundleIDText, prompt: Text("Bundle identifier, e.g. com.apple.Safari"))
                    .labelsHidden()
                HStack(spacing: LeafiyDesign.Spacing.s) {
                    Picker("Mode", selection: $newMode) {
                        Text("Always sensitive").tag(AppPrivacyMode.sensitive)
                        Text("Memory only").tag(AppPrivacyMode.memoryOnly)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("Add", action: addRule)
                        .disabled(bundleIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: reloadRules)
    }

    private func ruleRow(_ rule: AppPrivacyRule) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(rule.appName?.isEmpty == false ? rule.appName! : rule.bundleID).lineLimit(1)
                Text(rule.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(rule.mode == .sensitive ? "Sensitive" : "Memory only")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                removeRule(bundleID: rule.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func reloadRules() {
        rules = (try? appState.appPrivacyStore?.rules() ?? []) ?? []
    }

    private func addRule() {
        let trimmed = bundleIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try appState.appPrivacyStore?.setRule(bundleID: trimmed, appName: nil, mode: newMode)
            bundleIDText = ""
            reloadRules()
            appState.reloadMonitor()
            message = ""
        } catch {
            message = "Couldn't add rule."
        }
    }

    private func removeRule(bundleID: String) {
        do {
            try appState.appPrivacyStore?.removeRule(bundleID: bundleID)
            reloadRules()
            appState.reloadMonitor()
        } catch {
            message = "Couldn't remove rule."
        }
    }

    private func privacyBool(_ keyPath: WritableKeyPath<PrivacySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.privacy[keyPath: keyPath] },
            set: { newValue in settingsStore.update { $0.privacy[keyPath: keyPath] = newValue } }
        )
    }

    private var handlingBinding: Binding<SensitiveHandling> {
        Binding(
            get: { settingsStore.settings.privacy.handling },
            set: { newValue in settingsStore.update { $0.privacy.handling = newValue } }
        )
    }

    private var autoDeleteBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.privacy.autoDeleteSeconds },
            set: { newValue in settingsStore.update { $0.privacy.autoDeleteSeconds = min(max(newValue, 5), 3600) } }
        )
    }
}
