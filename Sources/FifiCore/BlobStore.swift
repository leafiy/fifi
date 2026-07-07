import Foundation

/// Encrypts blob payloads at rest. Implementations must be authenticated
/// (tampering fails `open`) and safe to call from any thread.
public protocol BlobCipher: Sendable {
    func seal(_ data: Data) throws -> Data
    func open(_ data: Data) throws -> Data
}

public enum BlobStoreError: Error {
    case encryptedBlobWithoutCipher(String)
}

// @unchecked: FileManager is thread-safe; `cipher` is only touched under `cipherLock`.
public final class BlobStore: @unchecked Sendable {
    /// Prefix marking encrypted blob files; legacy plaintext blobs lack it
    /// and stay readable after encryption is enabled.
    private static let encryptionMagic = Data("fifi-enc1".utf8)

    private let rootDirectory: URL
    private let blobsDirectory: URL
    private let thumbnailsDirectory: URL
    private let fileManager: FileManager
    private let cipherLock = NSLock()
    private var cipher: BlobCipher?

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.blobsDirectory = rootDirectory.appendingPathComponent("blobs", isDirectory: true)
        self.thumbnailsDirectory = rootDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        self.fileManager = .default

        try fileManager.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    /// Enables or disables at-rest encryption for newly written blobs.
    /// Existing files keep their format; reads handle both transparently.
    public func setCipher(_ cipher: BlobCipher?) {
        cipherLock.lock()
        defer { cipherLock.unlock() }
        self.cipher = cipher
    }

    public var hasCipher: Bool {
        cipherLock.lock()
        defer { cipherLock.unlock() }
        return cipher != nil
    }

    public func storeBlob(_ data: Data, hash: String, fileExtension: String) throws -> String {
        let ext = normalizedExtension(fileExtension)
        let filename = ext.isEmpty ? hash : "\(hash).\(ext)"
        let relativePath = "blobs/\(filename)"
        let url = url(forRelativePath: relativePath)
        if !fileManager.fileExists(atPath: url.path) {
            try outboundPayload(for: data).write(to: url, options: .atomic)
        }
        return relativePath
    }

    public func storeThumbnail(_ data: Data, hash: String) throws -> String {
        let relativePath = "thumbnails/\(hash).png"
        let url = url(forRelativePath: relativePath)
        if !fileManager.fileExists(atPath: url.path) {
            try outboundPayload(for: data).write(to: url, options: .atomic)
        }
        return relativePath
    }

    public func data(atRelativePath path: String) throws -> Data {
        let raw = try Data(contentsOf: url(forRelativePath: path))
        guard raw.starts(with: Self.encryptionMagic) else { return raw }
        guard let cipher = currentCipher() else {
            throw BlobStoreError.encryptedBlobWithoutCipher(path)
        }
        return try cipher.open(raw.dropFirst(Self.encryptionMagic.count))
    }

    private func currentCipher() -> BlobCipher? {
        cipherLock.lock()
        defer { cipherLock.unlock() }
        return cipher
    }

    private func outboundPayload(for data: Data) throws -> Data {
        guard let cipher = currentCipher() else { return data }
        return Self.encryptionMagic + (try cipher.seal(data))
    }

    public func url(forRelativePath path: String) -> URL {
        rootDirectory.appendingPathComponent(path)
    }

    /// Root directory containing the `blobs/` and `thumbnails/` subdirectories.
    public var directoryURL: URL { rootDirectory }

    /// Payload subdirectories, for backup/restore copies.
    public var payloadDirectories: [URL] { [blobsDirectory, thumbnailsDirectory] }

    public func delete(relativePath: String) {
        try? fileManager.removeItem(at: url(forRelativePath: relativePath))
    }

    public func deleteAll() {
        try? fileManager.removeItem(at: blobsDirectory)
        try? fileManager.removeItem(at: thumbnailsDirectory)
        try? fileManager.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    public func totalBytes() -> Int {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else {
            return 0
        }

        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
        }
        return total
    }

    // MARK: - Paths

    private func normalizedExtension(_ fileExtension: String) -> String {
        var value = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.first == "." {
            value.removeFirst()
        }
        return value
    }
}
