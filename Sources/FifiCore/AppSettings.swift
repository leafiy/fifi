import Foundation

public enum SelectionBehavior: String, CaseIterable, Sendable, Codable {
    case paste, copy
}

public enum AppearanceMode: String, CaseIterable, Sendable, Codable {
    case system, light, dark
}

public enum RowDensity: String, CaseIterable, Sendable, Codable {
    case comfortable, compact
}

public enum SensitiveHandling: String, CaseIterable, Sendable, Codable {
    /// Sensitive captures are never recorded.
    case ignore
    /// Sensitive captures are recorded, then deleted after a short delay.
    case autoDelete = "auto_delete"
}

public enum QuickShareProvider: String, CaseIterable, Sendable, Codable {
    case s3Compatible = "s3_compatible"
    case aliyunOSS = "aliyun_oss"
    case tencentCOS = "tencent_cos"
    case awsS3 = "aws_s3"
    case cloudflareR2 = "cloudflare_r2"
}

public struct QuickShareSettings: Sendable, Equatable, Codable {
    public var provider: QuickShareProvider
    public var endpointURL: String
    public var region: String
    public var bucket: String
    public var accessKeyID: String
    public var secretAccessKey: String
    public var keyPrefix: String

    public init(
        provider: QuickShareProvider = .s3Compatible,
        endpointURL: String = "",
        region: String = "",
        bucket: String = "",
        accessKeyID: String = "",
        secretAccessKey: String = "",
        keyPrefix: String = "fifi"
    ) {
        self.provider = provider
        self.endpointURL = endpointURL
        self.region = region
        self.bucket = bucket
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.keyPrefix = keyPrefix
    }

    public var isConfigured: Bool {
        !endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = QuickShareSettings()
        provider = try container.decodeIfPresent(QuickShareProvider.self, forKey: .provider) ?? defaults.provider
        endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL) ?? defaults.endpointURL
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? defaults.region
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? defaults.bucket
        accessKeyID = try container.decodeIfPresent(String.self, forKey: .accessKeyID) ?? defaults.accessKeyID
        secretAccessKey = try container.decodeIfPresent(String.self, forKey: .secretAccessKey) ?? defaults.secretAccessKey
        keyPrefix = try container.decodeIfPresent(String.self, forKey: .keyPrefix) ?? defaults.keyPrefix
    }
}

public struct PrivacySettings: Sendable, Equatable, Codable {
    /// Skip pasteboard writes marked `org.nspasteboard.ConcealedType`
    /// (password managers). On by default, matching V1 behavior.
    public var skipConcealed: Bool
    public var detectCreditCards: Bool
    public var detectAPIKeys: Bool
    public var detectVerificationCodes: Bool
    public var handling: SensitiveHandling
    public var autoDeleteSeconds: Int
    /// Captures are kept in memory only and never written to disk.
    public var privateMode: Bool
    /// Encrypt blob payloads (images, large text) at rest.
    public var encryptBlobs: Bool

    public init(
        skipConcealed: Bool = true,
        detectCreditCards: Bool = false,
        detectAPIKeys: Bool = false,
        detectVerificationCodes: Bool = false,
        handling: SensitiveHandling = .autoDelete,
        autoDeleteSeconds: Int = 60,
        privateMode: Bool = false,
        encryptBlobs: Bool = false
    ) {
        self.skipConcealed = skipConcealed
        self.detectCreditCards = detectCreditCards
        self.detectAPIKeys = detectAPIKeys
        self.detectVerificationCodes = detectVerificationCodes
        self.handling = handling
        self.autoDeleteSeconds = autoDeleteSeconds
        self.privateMode = privateMode
        self.encryptBlobs = encryptBlobs
    }

    public var detectionOptions: SensitiveDetectionOptions {
        SensitiveDetectionOptions(
            detectCreditCards: detectCreditCards,
            detectAPIKeys: detectAPIKeys,
            detectVerificationCodes: detectVerificationCodes
        )
    }

    // Tolerant decoding: every field falls back to its default so settings
    // written by older builds (or partial imports) keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PrivacySettings()
        skipConcealed = try container.decodeIfPresent(Bool.self, forKey: .skipConcealed) ?? defaults.skipConcealed
        detectCreditCards = try container.decodeIfPresent(Bool.self, forKey: .detectCreditCards) ?? defaults.detectCreditCards
        detectAPIKeys = try container.decodeIfPresent(Bool.self, forKey: .detectAPIKeys) ?? defaults.detectAPIKeys
        detectVerificationCodes = try container.decodeIfPresent(Bool.self, forKey: .detectVerificationCodes) ?? defaults.detectVerificationCodes
        handling = try container.decodeIfPresent(SensitiveHandling.self, forKey: .handling) ?? defaults.handling
        autoDeleteSeconds = try container.decodeIfPresent(Int.self, forKey: .autoDeleteSeconds) ?? defaults.autoDeleteSeconds
        privateMode = try container.decodeIfPresent(Bool.self, forKey: .privateMode) ?? defaults.privateMode
        encryptBlobs = try container.decodeIfPresent(Bool.self, forKey: .encryptBlobs) ?? defaults.encryptBlobs
    }
}

public struct AppSettings: Sendable, Equatable, Codable {
    public var hotkeyShortcut: String
    public var selectionBehavior: SelectionBehavior
    public var maxHistoryCount: Int
    public var retentionDays: Int
    public var maxStorageMB: Int
    public var launchAtLogin: Bool
    public var isRecordingPaused: Bool
    public var appLanguage: String
    public var appearance: AppearanceMode
    public var rowDensity: RowDensity
    public var pickerWidth: Int
    public var pickerHeight: Int
    public var showPreviewPanel: Bool
    public var showPickerFilters: Bool
    public var showSourceApp: Bool
    public var numberShortcuts: Bool
    public var sortOrder: HistorySortOrder
    public var fuzzyRanking: Bool
    public var privacy: PrivacySettings
    public var quickShare: QuickShareSettings

    public init(
        hotkeyShortcut: String = "cmd+shift+v",
        selectionBehavior: SelectionBehavior = .paste,
        maxHistoryCount: Int = 1000,
        retentionDays: Int = 30,
        maxStorageMB: Int = 512,
        launchAtLogin: Bool = false,
        isRecordingPaused: Bool = false,
        appLanguage: String = "system",
        appearance: AppearanceMode = .system,
        rowDensity: RowDensity = .comfortable,
        pickerWidth: Int = 420,
        pickerHeight: Int = 480,
        showPreviewPanel: Bool = false,
        showPickerFilters: Bool = false,
        showSourceApp: Bool = true,
        numberShortcuts: Bool = true,
        sortOrder: HistorySortOrder = .recency,
        fuzzyRanking: Bool = false,
        privacy: PrivacySettings = PrivacySettings(),
        quickShare: QuickShareSettings = QuickShareSettings()
    ) {
        self.hotkeyShortcut = hotkeyShortcut
        self.selectionBehavior = selectionBehavior
        self.maxHistoryCount = maxHistoryCount
        self.retentionDays = retentionDays
        self.maxStorageMB = maxStorageMB
        self.launchAtLogin = launchAtLogin
        self.isRecordingPaused = isRecordingPaused
        self.appLanguage = appLanguage
        self.appearance = appearance
        self.rowDensity = rowDensity
        self.pickerWidth = pickerWidth
        self.pickerHeight = pickerHeight
        self.showPreviewPanel = showPreviewPanel
        self.showPickerFilters = showPickerFilters
        self.showSourceApp = showSourceApp
        self.numberShortcuts = numberShortcuts
        self.sortOrder = sortOrder
        self.fuzzyRanking = fuzzyRanking
        self.privacy = privacy
        self.quickShare = quickShare
    }

    // Tolerant decoding: V1 settings JSON lacks every V2 key; missing keys
    // fall back to defaults instead of failing the whole decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        hotkeyShortcut = try container.decodeIfPresent(String.self, forKey: .hotkeyShortcut) ?? defaults.hotkeyShortcut
        selectionBehavior = try container.decodeIfPresent(SelectionBehavior.self, forKey: .selectionBehavior) ?? defaults.selectionBehavior
        maxHistoryCount = try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? defaults.maxHistoryCount
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? defaults.retentionDays
        maxStorageMB = try container.decodeIfPresent(Int.self, forKey: .maxStorageMB) ?? defaults.maxStorageMB
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        isRecordingPaused = try container.decodeIfPresent(Bool.self, forKey: .isRecordingPaused) ?? defaults.isRecordingPaused
        appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? defaults.appLanguage
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? defaults.appearance
        rowDensity = try container.decodeIfPresent(RowDensity.self, forKey: .rowDensity) ?? defaults.rowDensity
        pickerWidth = try container.decodeIfPresent(Int.self, forKey: .pickerWidth) ?? defaults.pickerWidth
        pickerHeight = try container.decodeIfPresent(Int.self, forKey: .pickerHeight) ?? defaults.pickerHeight
        showPreviewPanel = try container.decodeIfPresent(Bool.self, forKey: .showPreviewPanel) ?? defaults.showPreviewPanel
        showPickerFilters = try container.decodeIfPresent(Bool.self, forKey: .showPickerFilters) ?? defaults.showPickerFilters
        showSourceApp = try container.decodeIfPresent(Bool.self, forKey: .showSourceApp) ?? defaults.showSourceApp
        numberShortcuts = try container.decodeIfPresent(Bool.self, forKey: .numberShortcuts) ?? defaults.numberShortcuts
        sortOrder = try container.decodeIfPresent(HistorySortOrder.self, forKey: .sortOrder) ?? defaults.sortOrder
        fuzzyRanking = try container.decodeIfPresent(Bool.self, forKey: .fuzzyRanking) ?? defaults.fuzzyRanking
        privacy = try container.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? defaults.privacy
        quickShare = try container.decodeIfPresent(QuickShareSettings.self, forKey: .quickShare) ?? defaults.quickShare
    }

    public var cleanupPolicy: CleanupPolicy {
        CleanupPolicy(
            maxCount: maxHistoryCount > 0 ? maxHistoryCount : nil,
            maxAgeDays: retentionDays > 0 ? retentionDays : nil,
            maxTotalBytes: maxStorageMB > 0 ? storageByteLimit : nil
        )
    }

    private var storageByteLimit: Int {
        let bytesPerMegabyte = 1_048_576
        guard maxStorageMB <= Int.max / bytesPerMegabyte else { return Int.max }
        return maxStorageMB * bytesPerMegabyte
    }
}
