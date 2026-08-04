import Foundation
import LeafiyUICore

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

    public init(
        skipConcealed: Bool = true,
        detectCreditCards: Bool = false,
        detectAPIKeys: Bool = false,
        detectVerificationCodes: Bool = false,
        handling: SensitiveHandling = .autoDelete,
        autoDeleteSeconds: Int = 60,
        privateMode: Bool = false
    ) {
        self.skipConcealed = skipConcealed
        self.detectCreditCards = detectCreditCards
        self.detectAPIKeys = detectAPIKeys
        self.detectVerificationCodes = detectVerificationCodes
        self.handling = handling
        self.autoDeleteSeconds = autoDeleteSeconds
        self.privateMode = privateMode
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
    }
}

public struct AppSettings: Sendable, Equatable, Codable, LeafiyAppSettings {
    public var hotkeyShortcut: String
    public var selectionBehavior: SelectionBehavior
    public var maxHistoryCount: Int
    public var retentionDays: Int
    public var maxStorageMB: Int
    public var launchAtLogin: Bool
    public var showDockIcon: Bool
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
    /// Window transparency for the picker panel — Fifi's main window. Off
    /// by default; the level is clamped to `windowOpacityRange`.
    public var windowOpacityEnabled: Bool
    public var windowOpacity: Double

    public static var defaults: AppSettings { AppSettings() }

    public init(
        hotkeyShortcut: String = "cmd+shift+v",
        selectionBehavior: SelectionBehavior = .paste,
        maxHistoryCount: Int = 1000,
        retentionDays: Int = 30,
        maxStorageMB: Int = 512,
        launchAtLogin: Bool = false,
        showDockIcon: Bool = true,
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
        quickShare: QuickShareSettings = QuickShareSettings(keyPrefix: "fifi"),
        windowOpacityEnabled: Bool = false,
        windowOpacity: Double = AppSettings.defaultWindowOpacity
    ) {
        self.hotkeyShortcut = hotkeyShortcut
        self.selectionBehavior = selectionBehavior
        self.maxHistoryCount = maxHistoryCount
        self.retentionDays = retentionDays
        self.maxStorageMB = maxStorageMB
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
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
        self.windowOpacityEnabled = windowOpacityEnabled
        self.windowOpacity = AppSettings.clampedOpacity(windowOpacity)
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
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? defaults.showDockIcon
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
        windowOpacityEnabled = try container.decodeIfPresent(Bool.self, forKey: .windowOpacityEnabled) ?? defaults.windowOpacityEnabled
        windowOpacity = AppSettings.clampedOpacity(try container.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? defaults.windowOpacity)
    }

    // MARK: - Window transparency

    /// Fully opaque is the top of the range; below `minWindowOpacity` the
    /// window stops being usable, so the slider bottoms out there.
    public static let minWindowOpacity: Double = 0.1
    public static let defaultWindowOpacity: Double = 0.9
    public static let windowOpacityRange: ClosedRange<Double> = minWindowOpacity...1

    public static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultWindowOpacity }
        return min(max(value, minWindowOpacity), 1)
    }

    /// The alpha the picker window should carry right now. Disabled means
    /// fully opaque regardless of the stored level.
    public var currentWindowOpacity: Double {
        windowOpacityEnabled ? windowOpacity : 1
    }

    /// A translucent window that shows a razor-sharp desktop through it is
    /// unreadable, so transparency drags a frosted backdrop along with it.
    /// The strength is derived, never configured: none at fully opaque,
    /// rising to `maxWindowBlur` at `minWindowOpacity`. It stops short of 1
    /// so the window keeps some of its own colour at every level.
    public static let maxWindowBlur: Double = 0.8

    public static func windowBlur(forOpacity opacity: Double) -> Double {
        let transparency = (1 - clampedOpacity(opacity)) / (1 - minWindowOpacity)
        return maxWindowBlur * transparency
    }

    /// Blur strength that pairs with `currentWindowOpacity`; zero while
    /// transparency is off, since the window is then fully opaque.
    public var windowBlurIntensity: Double {
        windowOpacityEnabled ? AppSettings.windowBlur(forOpacity: windowOpacity) : 0
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
