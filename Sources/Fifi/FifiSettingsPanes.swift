import AppKit
import FifiCore
import LeafiyUI
import SwiftUI

struct PickerSettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsPane(L("Picker"), systemImage: "rectangle.and.text.magnifyingglass", height: 420) {
            Section(L("Layout")) {
                stepperRow(L("Width"), binding: intBinding(\.pickerWidth, lower: 320, upper: 900), range: 320...900, step: 20)
                stepperRow(L("Height"), binding: intBinding(\.pickerHeight, lower: 320, upper: 1000), range: 320...1000, step: 20)
                Picker(L("Row density"), selection: densityBinding) {
                    Text(L("Comfortable")).tag(RowDensity.comfortable)
                    Text(L("Compact")).tag(RowDensity.compact)
                }
                Toggle(L("Show picker preview"), isOn: boolBinding(\.showPreviewPanel))
            }
            Section(L("Search")) {
                Toggle(L("Show filters in picker"), isOn: boolBinding(\.showPickerFilters))
                Toggle(L("Show app source"), isOn: boolBinding(\.showSourceApp))
                Picker(L("Sort order"), selection: sortBinding) {
                    Text(L("Most recent")).tag(HistorySortOrder.recency)
                    Text(L("Most used")).tag(HistorySortOrder.mostUsed)
                }
                Toggle(L("Fuzzy ranking"), isOn: boolBinding(\.fuzzyRanking))
                Toggle(L("Number shortcuts (⌘1–0)"), isOn: boolBinding(\.numberShortcuts))
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
        SettingsPane(L("Privacy"), systemImage: "hand.raised.square", height: 520) {
            Section(L("Detection")) {
                Toggle(L("Skip password-manager items"), isOn: privacyBool(\.skipConcealed))
                Toggle(L("Detect credit card numbers"), isOn: privacyBool(\.detectCreditCards))
                Toggle(L("Detect API keys and tokens"), isOn: privacyBool(\.detectAPIKeys))
                Toggle(L("Detect verification codes"), isOn: privacyBool(\.detectVerificationCodes))
            }
            Section(L("Sensitive handling")) {
                Picker(L("When detected"), selection: handlingBinding) {
                    Text(L("Don’t record")).tag(SensitiveHandling.ignore)
                    Text(L("Auto-delete after delay")).tag(SensitiveHandling.autoDelete)
                }
                if settingsStore.settings.privacy.handling == .autoDelete {
                    HStack {
                        Text(L("Delete after (seconds)"))
                        Spacer()
                        TextField(L("Seconds"), value: autoDeleteBinding, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Stepper(L("Seconds"), value: autoDeleteBinding, in: 5...3600, step: 5)
                            .labelsHidden()
                    }
                }
            }
            Section(L("Modes")) {
                Toggle(L("Private mode (memory only)"), isOn: privacyBool(\.privateMode))
                Toggle(L("Encrypt stored images and large text"), isOn: privacyBool(\.encryptBlobs))
                Text(L("Private mode keeps captures in memory and never writes them to disk. Encryption protects blob files at rest; search text stays indexed for speed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Per-App Privacy")) {
                if rules.isEmpty {
                    Text(L("No per-app rules"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }
                }
                TextField(L("Bundle identifier"), text: $bundleIDText, prompt: Text(L("Bundle identifier, e.g. com.apple.Safari")))
                    .labelsHidden()
                HStack(spacing: LeafiyDesign.Spacing.s) {
                    Picker(L("Mode"), selection: $newMode) {
                        Text(L("Always sensitive")).tag(AppPrivacyMode.sensitive)
                        Text(L("Memory only")).tag(AppPrivacyMode.memoryOnly)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button(L("Add"), action: addRule)
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
            Text(rule.mode == .sensitive ? L("Sensitive") : L("Memory only"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                removeRule(bundleID: rule.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(L("Remove"))
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
            message = L("Couldn’t add rule.")
        }
    }

    private func removeRule(bundleID: String) {
        do {
            try appState.appPrivacyStore?.removeRule(bundleID: bundleID)
            reloadRules()
            appState.reloadMonitor()
        } catch {
            message = L("Couldn’t remove rule.")
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

struct ShareSettingsPane: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsPane(L("Share"), systemImage: "square.and.arrow.up", height: 560) {
            Section(L("Quick Share")) {
                Picker(L("Provider"), selection: providerBinding) {
                    ForEach(QuickShareProvider.allCases, id: \.self) { provider in
                        Text(provider.fifiLabel).tag(provider)
                    }
                }
                Text(L("Quick Share uploads the selected item to your public object storage and copies the public URL to the clipboard."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Storage account")) {
                TextField(
                    L("Endpoint URL"),
                    text: shareString(\.endpointURL),
                    prompt: Text(L("https://s3.us-west-2.amazonaws.com"))
                )
                TextField(L("Region"), text: shareString(\.region), prompt: Text("us-west-2"))
                TextField(L("Bucket"), text: shareString(\.bucket), prompt: Text("my-public-bucket"))
                TextField(L("Access Key"), text: shareString(\.accessKeyID))
                SecureField(L("Secret Key"), text: shareString(\.secretAccessKey))
            }
            Section(L("Public URL")) {
                TextField(L("Object prefix"), text: shareString(\.keyPrefix), prompt: Text("fifi"))
                Text(L("Fifi builds the public URL from Endpoint, Bucket, Object prefix, and the generated filename."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Quick guide")) {
                Text(L("1. Create a bucket or prefix that is public-read.\n2. Create a least-privileged key that can PutObject only to that bucket or prefix.\n3. Fill Endpoint, Region, Bucket, Access Key, Secret Key, and Object prefix.\nExamples: Alibaba OSS endpoint https://oss-cn-hangzhou.aliyuncs.com or https://<bucket>.oss-cn-hangzhou.aliyuncs.com; Tencent COS endpoint https://cos.ap-shanghai.myqcloud.com or https://<bucket>.cos.ap-shanghai.myqcloud.com; AWS S3 endpoint https://s3.us-west-2.amazonaws.com; Cloudflare R2 endpoint https://<account-id>.r2.cloudflarestorage.com with region auto."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var providerBinding: Binding<QuickShareProvider> {
        Binding(
            get: { settingsStore.settings.quickShare.provider },
            set: { newValue in settingsStore.update { $0.quickShare.provider = newValue } }
        )
    }

    private func shareString(_ keyPath: WritableKeyPath<QuickShareSettings, String>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings.quickShare[keyPath: keyPath] },
            set: { newValue in settingsStore.update { $0.quickShare[keyPath: keyPath] = newValue } }
        )
    }
}

extension QuickShareProvider {
    var fifiLabel: String {
        switch self {
        case .s3Compatible: return L("S3-compatible")
        case .aliyunOSS: return L("Alibaba Cloud OSS")
        case .tencentCOS: return L("Tencent Cloud COS")
        case .awsS3: return L("AWS S3")
        case .cloudflareR2: return L("Cloudflare R2")
        }
    }
}
