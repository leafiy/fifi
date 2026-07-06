import Foundation

public struct PixelSize: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int = 0, height: Int = 0) {
        self.width = width
        self.height = height
    }
}

public struct CaptureCandidate: Sendable {
    public var plainText: String?
    public var hasRichText: Bool
    public var urlString: String?
    public var filePaths: [String]
    public var imageData: Data?
    public var imageUTI: String?
    public var imagePixelSize: PixelSize?
    public var rawTypes: [String]
    public var sourceAppName: String?
    public var sourceAppBundleID: String?

    public init(
        plainText: String? = nil,
        hasRichText: Bool = false,
        urlString: String? = nil,
        filePaths: [String] = [],
        imageData: Data? = nil,
        imageUTI: String? = nil,
        imagePixelSize: PixelSize? = nil,
        rawTypes: [String] = [],
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.plainText = plainText
        self.hasRichText = hasRichText
        self.urlString = urlString
        self.filePaths = filePaths
        self.imageData = imageData
        self.imageUTI = imageUTI
        self.imagePixelSize = imagePixelSize
        self.rawTypes = rawTypes
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
    }
}

public struct ClassifiedCapture: Sendable {
    public var type: ClipItemType
    public var previewText: String
    public var contentText: String?
    public var searchText: String
    public var byteSize: Int
    public var fileReference: String?
    public var metadataJSON: String?
    public var hashInput: Data
    public var needsTextBlob: Bool
    public var largeText: String?

    public init(
        type: ClipItemType,
        previewText: String,
        contentText: String? = nil,
        searchText: String = "",
        byteSize: Int = 0,
        fileReference: String? = nil,
        metadataJSON: String? = nil,
        hashInput: Data = Data(),
        needsTextBlob: Bool = false,
        largeText: String? = nil
    ) {
        self.type = type
        self.previewText = previewText
        self.contentText = contentText
        self.searchText = searchText
        self.byteSize = byteSize
        self.fileReference = fileReference
        self.metadataJSON = metadataJSON
        self.hashInput = hashInput
        self.needsTextBlob = needsTextBlob
        self.largeText = largeText
    }
}

public enum ClipboardClassifier {
    public static let maxInlineTextBytes = 128 * 1024

    public static func classify(_ candidate: CaptureCandidate) -> ClassifiedCapture? {
        let appName = nonEmpty(candidate.sourceAppName)
        let paths = candidate.filePaths.filter { !$0.isEmpty }
        if !paths.isEmpty {
            let fileReference = paths.joined(separator: "\n")
            let sortedReference = paths.sorted().joined(separator: "\n")
            let fileTerms = paths.flatMap { [$0, fileName(for: $0)] }
            return ClassifiedCapture(
                type: .file,
                previewText: collapsedPreview(fileReference),
                searchText: joinedSearchText(fileTerms.map { Optional($0) } + [appName]),
                byteSize: 0,
                fileReference: fileReference,
                metadataJSON: metadataJSON(["count": paths.count]),
                hashInput: Data(sortedReference.utf8)
            )
        }

        if let imageData = candidate.imageData, !imageData.isEmpty {
            var metadata: [String: Any] = [:]
            var preview = "Image"
            if let size = candidate.imagePixelSize {
                metadata["width"] = size.width
                metadata["height"] = size.height
                if size.width > 0, size.height > 0 {
                    preview = "Image \(size.width)×\(size.height)"
                }
            }
            if let uti = nonEmpty(candidate.imageUTI) {
                metadata["uti"] = uti
            }
            return ClassifiedCapture(
                type: .image,
                previewText: preview,
                searchText: joinedSearchText([appName]),
                byteSize: imageData.count,
                metadataJSON: metadataJSON(metadata),
                hashInput: imageData
            )
        }

        if let explicitURL = nonEmpty(candidate.urlString) {
            return textCapture(
                type: .url,
                text: explicitURL,
                previewText: collapsedPreview(explicitURL),
                searchText: joinedSearchText([explicitURL, appName]),
                metadataJSON: urlMetadataJSON(explicitURL)
            )
        }

        if let text = candidate.plainText {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = httpURL(from: trimmedText) {
                return textCapture(
                    type: .url,
                    text: text,
                    previewText: collapsedPreview(text),
                    searchText: joinedSearchText([text, appName]),
                    metadataJSON: domainMetadataJSON(url)
                )
            }

            if hexColorComponents(trimmedText) != nil {
                return textCapture(
                    type: .color,
                    text: text,
                    previewText: collapsedPreview(text),
                    searchText: joinedSearchText([text, appName])
                )
            }

            if !text.isEmpty {
                return textCapture(
                    type: candidate.hasRichText ? .richText : .text,
                    text: text,
                    previewText: collapsedPreview(text),
                    searchText: joinedSearchText([text, appName])
                )
            }
        }

        let rawTypes = candidate.rawTypes.filter { !$0.isEmpty }
        if !rawTypes.isEmpty {
            let sortedTypes = rawTypes.sorted()
            let joinedTypes = sortedTypes.joined(separator: "\n")
            return ClassifiedCapture(
                type: .unknown,
                previewText: collapsedPreview(joinedTypes),
                searchText: joinedSearchText(sortedTypes.map { Optional($0) } + [appName]),
                byteSize: 0,
                metadataJSON: metadataJSON(["types": sortedTypes]),
                hashInput: Data(joinedTypes.utf8)
            )
        }

        return nil
    }

    public static func hexColorComponents(_ text: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hex = String(trimmed.dropFirst())
        guard [3, 6, 8].contains(hex.count), hex.allSatisfy(isHexDigit) else { return nil }

        if hex.count == 3 {
            let values = hex.compactMap { Int(String($0), radix: 16) }
            guard values.count == 3 else { return nil }
            return (Double(values[0]) / 15.0, Double(values[1]) / 15.0, Double(values[2]) / 15.0, 1.0)
        }

        guard let r = byte(hex, start: 0), let g = byte(hex, start: 2), let b = byte(hex, start: 4) else {
            return nil
        }
        let alpha = hex.count == 8 ? byte(hex, start: 6) : 255
        guard let a = alpha else { return nil }
        return (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0, Double(a) / 255.0)
    }

    private static func textCapture(
        type: ClipItemType,
        text: String,
        previewText: String,
        searchText: String,
        metadataJSON: String? = nil
    ) -> ClassifiedCapture {
        let byteSize = text.utf8.count
        let needsBlob = byteSize > maxInlineTextBytes
        return ClassifiedCapture(
            type: type,
            previewText: previewText,
            contentText: needsBlob ? nil : text,
            searchText: searchText,
            byteSize: byteSize,
            metadataJSON: metadataJSON,
            hashInput: Data(text.utf8),
            needsTextBlob: needsBlob,
            largeText: needsBlob ? text : nil
        )
    }

    private static func collapsedPreview(_ text: String, limit: Int = 512) -> String {
        guard limit > 0 else { return "" }
        var output = ""
        output.reserveCapacity(limit)
        var pendingSpace = false
        var count = 0

        for character in text {
            let isWhitespace = character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
            if isWhitespace {
                if !output.isEmpty {
                    pendingSpace = true
                }
                continue
            }
            if pendingSpace {
                output.append(" ")
                count += 1
                pendingSpace = false
                if count >= limit { break }
            }
            output.append(character)
            count += 1
            if count >= limit { break }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinedSearchText(_ parts: [String?]) -> String {
        parts.compactMap { nonEmpty($0) }.joined(separator: " ")
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static func fileName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func httpURL(from string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private static func urlMetadataJSON(_ string: String) -> String? {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { return nil }
        return metadataJSON(["domain": host])
    }

    private static func domainMetadataJSON(_ url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        return metadataJSON(["domain": host])
    }

    private static func metadataJSON(_ object: [String: Any]) -> String? {
        guard !object.isEmpty, JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object), let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        switch scalar.value {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }

    private static func byte(_ text: String, start: Int) -> Int? {
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(startIndex, offsetBy: 2)
        return Int(text[startIndex..<endIndex], radix: 16)
    }
}
