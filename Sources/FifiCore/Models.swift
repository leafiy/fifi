import Foundation

public enum ClipItemType: String, CaseIterable, Sendable, Codable {
    case text, richText = "rich_text", url, image, color, file, unknown
}

public struct ClipboardItem: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var contentHash: String
    public var type: ClipItemType
    public var previewText: String
    public var contentText: String?
    public var sourceAppName: String?
    public var sourceAppBundleID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var isPinned: Bool
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var byteSize: Int
    public var blobPath: String?
    public var thumbnailPath: String?
    public var fileReference: String?
    public var metadataJSON: String?

    public init(
        id: Int64 = 0,
        contentHash: String = "",
        type: ClipItemType = .unknown,
        previewText: String = "",
        contentText: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        byteSize: Int = 0,
        blobPath: String? = nil,
        thumbnailPath: String? = nil,
        fileReference: String? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.type = type
        self.previewText = previewText
        self.contentText = contentText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.byteSize = byteSize
        self.blobPath = blobPath
        self.thumbnailPath = thumbnailPath
        self.fileReference = fileReference
        self.metadataJSON = metadataJSON
    }
}

public struct NewClipboardItem: Sendable {
    public var contentHash: String
    public var type: ClipItemType
    public var previewText: String
    public var contentText: String?
    public var searchText: String
    public var sourceAppName: String?
    public var sourceAppBundleID: String?
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var byteSize: Int
    public var blobPath: String?
    public var thumbnailPath: String?
    public var fileReference: String?
    public var metadataJSON: String?

    public init(
        contentHash: String = "",
        type: ClipItemType = .unknown,
        previewText: String = "",
        contentText: String? = nil,
        searchText: String = "",
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        byteSize: Int = 0,
        blobPath: String? = nil,
        thumbnailPath: String? = nil,
        fileReference: String? = nil,
        metadataJSON: String? = nil
    ) {
        self.contentHash = contentHash
        self.type = type
        self.previewText = previewText
        self.contentText = contentText
        self.searchText = searchText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.byteSize = byteSize
        self.blobPath = blobPath
        self.thumbnailPath = thumbnailPath
        self.fileReference = fileReference
        self.metadataJSON = metadataJSON
    }
}
