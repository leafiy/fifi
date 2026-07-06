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
    public var pollingIntervalMS: Int

    public init(
        hotkeyShortcut: String = "cmd+shift+v",
        selectionBehavior: SelectionBehavior = .paste,
        maxHistoryCount: Int = 1000,
        retentionDays: Int = 30,
        maxStorageMB: Int = 512,
        launchAtLogin: Bool = false,
        isRecordingPaused: Bool = false,
        pollingIntervalMS: Int = 150
    ) {
        self.hotkeyShortcut = hotkeyShortcut
        self.selectionBehavior = selectionBehavior
        self.maxHistoryCount = maxHistoryCount
        self.retentionDays = retentionDays
        self.maxStorageMB = maxStorageMB
        self.launchAtLogin = launchAtLogin
        self.isRecordingPaused = isRecordingPaused
        self.pollingIntervalMS = pollingIntervalMS
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
