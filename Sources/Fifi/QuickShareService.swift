import AppKit
import CryptoKit
import FifiCore
import Foundation
import UniformTypeIdentifiers

enum QuickShareError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case missingPayload
    case foldersUnsupported(String)
    case uploadFailed(Int, String)

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
        guard settings.isConfigured else { throw QuickShareError.notConfigured }
        let config = try UploadConfig(settings: settings)
        let payloads = try payloads(for: item)
        guard !payloads.isEmpty else { throw QuickShareError.missingPayload }

        var links: [String] = []
        for (index, payload) in payloads.enumerated() {
            let key = objectKey(for: item, payload: payload, index: payloads.count == 1 ? nil : index, prefix: config.keyPrefix)
            try await upload(payload: payload, key: key, config: config)
            links.append(config.objectURL(for: key).absoluteString)
        }
        return QuickShareUploadResult(links: links)
    }

    private func payloads(for item: ClipboardItem) throws -> [QuickSharePayload] {
        switch item.type {
        case .image:
            guard let blobPath = item.blobPath else { throw QuickShareError.missingPayload }
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
            guard !value.isEmpty else { throw QuickShareError.missingPayload }
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
            throw QuickShareError.missingPayload
        }
        if isDirectory.boolValue {
            throw QuickShareError.foldersUnsupported(path)
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

    private func upload(payload: QuickSharePayload, key: String, config: UploadConfig) async throws {
        var request = URLRequest(url: config.uploadURL(for: key))
        request.httpMethod = "PUT"
        request.httpBody = payload.data
        request.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(payload.data.count), forHTTPHeaderField: "Content-Length")

        let signedHeaders = S3Signer.signedHeaders(
            method: "PUT",
            url: request.url!,
            body: payload.data,
            accessKeyID: config.accessKeyID,
            secretAccessKey: config.secretAccessKey,
            region: config.region
        )
        for (field, value) in signedHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw QuickShareError.uploadFailed(http.statusCode, body)
        }
    }

    private func objectKey(for item: ClipboardItem, payload: QuickSharePayload, index: Int?, prefix: String) -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        var base = "\(timestamp)-\(item.id)-\(sanitized(payload.filenameBase))"
        if let index {
            base += "-\(index + 1)"
        }
        let filename = "\(base).\(sanitizedExtension(payload.fileExtension))"
        guard !prefix.isEmpty else { return filename }
        return "\(prefix)/\(filename)"
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

private struct UploadConfig {
    let endpoint: URL
    let region: String
    let bucket: String
    let accessKeyID: String
    let secretAccessKey: String
    let keyPrefix: String
    let provider: QuickShareProvider

    init(settings: QuickShareSettings) throws {
        let endpointText = Self.normalizedEndpointText(settings.endpointURL)
        guard let endpoint = URL(string: endpointText), endpoint.scheme != nil, endpoint.host != nil else {
            throw QuickShareError.invalidEndpoint
        }
        self.endpoint = endpoint
        self.region = settings.region.trimmed
        self.bucket = settings.bucket.trimmed
        self.accessKeyID = settings.accessKeyID.trimmed
        self.secretAccessKey = settings.secretAccessKey
        self.keyPrefix = settings.keyPrefix.pathPrefix
        self.provider = settings.provider
    }

    private static func normalizedEndpointText(_ value: String) -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return trimmed }
        guard trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) == nil else {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    func uploadURL(for key: String) -> URL { objectURL(for: key) }

    func objectURL(for key: String) -> URL {
        if isBucketScopedEndpoint {
            return endpoint.appendingObjectKey(key)
        }
        if usesVirtualHostedStyle {
            return endpoint.withBucketHost(bucket).appendingObjectKey(key)
        }
        return endpoint.appendingPathComponent(bucket).appendingObjectKey(key)
    }

    private var usesVirtualHostedStyle: Bool {
        switch provider {
        case .aliyunOSS, .tencentCOS, .awsS3, .cloudflareR2:
            return true
        case .s3Compatible:
            return false
        }
    }

    private var isBucketScopedEndpoint: Bool {
        guard let host = endpoint.host?.lowercased(), !bucket.isEmpty else { return false }
        let normalizedBucket = bucket.lowercased()
        if host == normalizedBucket || host.hasPrefix("\(normalizedBucket).") {
            return true
        }
        return endpoint.path
            .split(separator: "/")
            .last
            .map { String($0).lowercased() == normalizedBucket } ?? false
    }
}

private enum S3Signer {
    static func signedHeaders(
        method: String,
        url: URL,
        body: Data,
        accessKeyID: String,
        secretAccessKey: String,
        region: String,
        now: Date = Date()
    ) -> [String: String] {
        let payloadHash = sha256Hex(body)
        let amzDate = amzDateFormatter.string(from: now)
        let date = shortDateFormatter.string(from: now)
        let host = url.hostWithPort

        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"
        let canonicalRequest = [
            method,
            canonicalURI(url.path),
            url.query ?? "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(date)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = signingKey(secretAccessKey: secretAccessKey, date: date, region: region)
        let signature = hmacHex(Data(stringToSign.utf8), key: signingKey)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        return [
            "Host": host,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": amzDate,
            "Authorization": authorization
        ]
    }

    private static func signingKey(secretAccessKey: String, date: String, region: String) -> SymmetricKey {
        let dateKey = hmac(Data(date.utf8), key: SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8)))
        let regionKey = hmac(Data(region.utf8), key: SymmetricKey(data: dateKey))
        let serviceKey = hmac(Data("s3".utf8), key: SymmetricKey(data: regionKey))
        let signingKey = hmac(Data("aws4_request".utf8), key: SymmetricKey(data: serviceKey))
        return SymmetricKey(data: signingKey)
    }

    private static func hmac(_ data: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func hmacHex(_ data: Data, key: SymmetricKey) -> String {
        hmac(data, key: key).hexString
    }

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }

    private static func canonicalURI(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.map { percentEncode(String($0)) }.joined(separator: "/")
    }

    private static func percentEncode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var output = ""
        for scalar in value.unicodeScalars {
            if unreserved.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    output += String(format: "%%%02X", byte)
                }
            }
        }
        return output
    }

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var pathPrefix: String {
        trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}

private extension URL {
    func withBucketHost(_ bucket: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let host = components.host,
              !bucket.isEmpty else {
            return self
        }
        components.host = "\(bucket).\(host)"
        return components.url ?? self
    }

    func appendingObjectKey(_ key: String) -> URL {
        key.split(separator: "/").reduce(self) { url, segment in
            url.appendingPathComponent(String(segment))
        }
    }

    var hostWithPort: String {
        guard let host else { return "" }
        if let port {
            return "\(host):\(port)"
        }
        return host
    }
}

extension Notification.Name {
    static let fifiQuickShareUploadStatusDidChange = Notification.Name("com.leafiy.fifi.quick-share-upload-status-did-change")
}
