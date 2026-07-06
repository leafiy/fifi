import Foundation

public final class BlobStore {
    private let rootDirectory: URL
    private let blobsDirectory: URL
    private let thumbnailsDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.blobsDirectory = rootDirectory.appendingPathComponent("blobs", isDirectory: true)
        self.thumbnailsDirectory = rootDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        self.fileManager = .default

        try fileManager.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    public func storeBlob(_ data: Data, hash: String, fileExtension: String) throws -> String {
        let ext = normalizedExtension(fileExtension)
        let filename = ext.isEmpty ? hash : "\(hash).\(ext)"
        let relativePath = "blobs/\(filename)"
        let url = url(forRelativePath: relativePath)
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return relativePath
    }

    public func storeThumbnail(_ data: Data, hash: String) throws -> String {
        let relativePath = "thumbnails/\(hash).png"
        let url = url(forRelativePath: relativePath)
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return relativePath
    }

    public func data(atRelativePath path: String) throws -> Data {
        try Data(contentsOf: url(forRelativePath: path))
    }

    public func url(forRelativePath path: String) -> URL {
        rootDirectory.appendingPathComponent(path)
    }

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
