import Foundation

public enum SelectionBehavior: String, CaseIterable, Sendable, Codable {
    case paste, copy
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

    public init(
        hotkeyShortcut: String = "cmd+shift+v",
        selectionBehavior: SelectionBehavior = .paste,
        maxHistoryCount: Int = 1000,
        retentionDays: Int = 30,
        maxStorageMB: Int = 512,
        launchAtLogin: Bool = false,
        isRecordingPaused: Bool = false,
        appLanguage: String = "system"
    ) {
        self.hotkeyShortcut = hotkeyShortcut
        self.selectionBehavior = selectionBehavior
        self.maxHistoryCount = maxHistoryCount
        self.retentionDays = retentionDays
        self.maxStorageMB = maxStorageMB
        self.launchAtLogin = launchAtLogin
        self.isRecordingPaused = isRecordingPaused
        self.appLanguage = appLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case hotkeyShortcut
        case selectionBehavior
        case maxHistoryCount
        case retentionDays
        case maxStorageMB
        case launchAtLogin
        case isRecordingPaused
        case appLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hotkeyShortcut: try container.decodeIfPresent(String.self, forKey: .hotkeyShortcut) ?? "cmd+shift+v",
            selectionBehavior: try container.decodeIfPresent(SelectionBehavior.self, forKey: .selectionBehavior) ?? .paste,
            maxHistoryCount: try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 1000,
            retentionDays: try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30,
            maxStorageMB: try container.decodeIfPresent(Int.self, forKey: .maxStorageMB) ?? 512,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            isRecordingPaused: try container.decodeIfPresent(Bool.self, forKey: .isRecordingPaused) ?? false,
            appLanguage: try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "system"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkeyShortcut, forKey: .hotkeyShortcut)
        try container.encode(selectionBehavior, forKey: .selectionBehavior)
        try container.encode(maxHistoryCount, forKey: .maxHistoryCount)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(maxStorageMB, forKey: .maxStorageMB)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(isRecordingPaused, forKey: .isRecordingPaused)
        try container.encode(appLanguage, forKey: .appLanguage)
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
