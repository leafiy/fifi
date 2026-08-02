import AppKit
import FifiCore
import Foundation
import LeafiyUICore
import UniformTypeIdentifiers

enum FifiQuickShareError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case missingPayload
    case foldersUnsupported(String)
    case uploadFailed(Int, String)

    init(_ sharedError: QuickShareError) {
        switch sharedError {
        case .notConfigured:
            self = .notConfigured
        case .invalidEndpoint:
            self = .invalidEndpoint
        case .uploadFailed(let status, let body):
            self = .uploadFailed(status, body)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("Set up Quick Share storage in Settings first.")
        case .invalidEndpoint:
            return L("The Quick Share endpoint URL is invalid.")
        case .missingPayload:
            return L("This item has no shareable payload.")
        case .foldersUnsupported(let path):
            return String(format: L("Quick Share can’t upload folders: %@"), path)
        case .uploadFailed(let status, let body):
            if body.isEmpty {
                return String(format: L("Quick Share upload failed with HTTP %d."), status)
            }
            return String(format: L("Quick Share upload failed with HTTP %1$d: %2$@"), status, body)
        }
    }
}

struct QuickShareUploadResult {
    let links: [String]

    var clipboardText: String {
        links.joined(separator: "\n")
    }
}

struct QuickSharePayload {
    let data: Data
    let filenameBase: String
    let fileExtension: String
    let contentType: String
}

final class QuickShareService {
    private let blobStore: BlobStore
    private let session: URLSession

    init(blobStore: BlobStore, session: URLSession = .shared) {
        self.blobStore = blobStore
        self.session = session
    }

    func share(item: ClipboardItem, settings: QuickShareSettings) async throws -> QuickShareUploadResult {
        guard settings.isConfigured else { throw FifiQuickShareError.notConfigured }
        let payloads = try payloads(for: item)
        guard !payloads.isEmpty else { throw FifiQuickShareError.missingPayload }

        let uploader = QuickShareUploader(settings: settings, session: session)
        var links: [String] = []
        for (index, payload) in payloads.enumerated() {
            let filename = objectFilename(for: item, payload: payload, index: payloads.count == 1 ? nil : index)
            do {
                let url = try await uploader.upload(
                    data: payload.data,
                    filename: filename,
                    contentType: payload.contentType
                )
                links.append(url.absoluteString)
            } catch let error as QuickShareError {
                throw FifiQuickShareError(error)
            }
        }
        return QuickShareUploadResult(links: links)
    }

    private func payloads(for item: ClipboardItem) throws -> [QuickSharePayload] {
        switch item.type {
        case .image:
            guard let blobPath = item.blobPath else { throw FifiQuickShareError.missingPayload }
            let data = try blobStore.data(atRelativePath: blobPath)
            let ext = URL(fileURLWithPath: blobPath).pathExtension.nilIfEmpty ?? "png"
            return [
                QuickSharePayload(
                    data: data,
                    filenameBase: "image",
                    fileExtension: ext,
                    contentType: contentType(forExtension: ext) ?? "image/png"
                )
            ]
        case .file:
            return try filePaths(for: item).map { path in
                try filePayload(path: path)
            }
        case .text, .richText, .url, .color, .unknown:
            let value = text(for: item)
            guard !value.isEmpty else { throw FifiQuickShareError.missingPayload }
            return [
                QuickSharePayload(
                    data: Data(value.utf8),
                    filenameBase: filenameBase(for: item),
                    fileExtension: "txt",
                    contentType: "text/plain; charset=utf-8"
                )
            ]
        }
    }

    private func text(for item: ClipboardItem) -> String {
        if let blobPath = item.blobPath,
           let data = try? blobStore.data(atRelativePath: blobPath),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return item.contentText ?? item.previewText
    }

    private func filePaths(for item: ClipboardItem) -> [String] {
        (item.fileReference ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func filePayload(path: String) throws -> QuickSharePayload {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw FifiQuickShareError.missingPayload
        }
        if isDirectory.boolValue {
            throw FifiQuickShareError.foldersUnsupported(path)
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.nilIfEmpty ?? "bin"
        return QuickSharePayload(
            data: data,
            filenameBase: url.deletingPathExtension().lastPathComponent.nilIfEmpty ?? "file",
            fileExtension: ext,
            contentType: contentType(forExtension: ext) ?? "application/octet-stream"
        )
    }

    private func objectFilename(for item: ClipboardItem, payload: QuickSharePayload, index: Int?) -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        var base = "\(timestamp)-\(item.id)-\(sanitized(payload.filenameBase))"
        if let index {
            base += "-\(index + 1)"
        }
        return "\(base).\(sanitizedExtension(payload.fileExtension))"
    }

    private func filenameBase(for item: ClipboardItem) -> String {
        switch item.type {
        case .url:
            return URL(string: item.contentText ?? item.previewText)?.host ?? "url"
        case .color:
            return "color"
        case .richText:
            return "rich-text"
        case .unknown:
            return "clipboard"
        default:
            let words = (item.contentText ?? item.previewText)
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .prefix(4)
                .joined(separator: "-")
            return words.nilIfEmpty ?? item.type.rawValue
        }
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_.")).nilIfEmpty ?? "item"
    }

    private func sanitizedExtension(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let ext = String(value.unicodeScalars.filter { allowed.contains($0) }).lowercased()
        return ext.nilIfEmpty ?? "bin"
    }

    private func contentType(forExtension ext: String) -> String? {
        UTType(filenameExtension: ext)?.preferredMIMEType
    }


    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}


extension Notification.Name {
    static let fifiQuickShareUploadStatusDidChange = Notification.Name("com.leafiy.fifi.quick-share-upload-status-did-change")
}
