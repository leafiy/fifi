import AppKit
import FifiCore
import Foundation
import LeafiyUI
import LeafiyUICore

/// The one Quick Share failure that is about clipboard history rather than
/// storage; everything else is a Base Library `QuickShareError`.
enum FifiQuickShareError: LocalizedError {
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return L("This item has no shareable payload.")
        }
    }
}

/// Turns a clipboard item into Quick Share payloads and uploads them through
/// the Base Library. Naming, signing, uploading, and link building all live
/// there; only the clipboard-to-payload mapping is fifi's.
final class QuickShareService {
    private let blobStore: BlobStore
    private let session: URLSession

    init(blobStore: BlobStore, session: URLSession = .shared) {
        self.blobStore = blobStore
        self.session = session
    }

    /// Uploads every payload of `item` and returns one Share Link per payload.
    func share(item: ClipboardItem, settings: QuickShareSettings) async throws -> [URL] {
        guard settings.isConfigured else { throw QuickShareError.notConfigured }
        let payloads = try payloads(for: item)
        guard !payloads.isEmpty else { throw FifiQuickShareError.missingPayload }
        return try await QuickShareUploader(settings: settings, session: session).upload(payloads)
    }

    private func payloads(for item: ClipboardItem) throws -> [QuickSharePayload] {
        switch item.type {
        case .image:
            guard let blobPath = item.blobPath else { throw FifiQuickShareError.missingPayload }
            let data = try blobStore.data(atRelativePath: blobPath)
            let ext = URL(fileURLWithPath: blobPath).pathExtension
            return [
                QuickSharePayload(
                    data: data,
                    filenameBase: "image",
                    fileExtension: ext.isEmpty ? "png" : ext
                )
            ]
        case .file:
            return try filePaths(for: item).map { path in
                try QuickSharePayload(fileURL: URL(fileURLWithPath: path))
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
            return words.isEmpty ? item.type.rawValue : words
        }
    }
}

extension Notification.Name {
    static let fifiQuickShareUploadStatusDidChange = Notification.Name("com.leafiy.fifi.quick-share-upload-status-did-change")
}
