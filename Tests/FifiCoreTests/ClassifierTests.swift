import Foundation
import XCTest
@testable import FifiCore

final class ClassifierTests: FifiCoreTestCase {
    func testClassifierPriorityOrder() throws {
        let fileCandidate = makeCandidate(
            plainText: "#abc",
            urlString: "https://example.com",
            filePaths: ["/Users/me/file.txt"],
            imageData: Data([1, 2, 3]),
            imageUTI: "public.png"
        )
        XCTAssertEqual(ClipboardClassifier.classify(fileCandidate)?.type, .file)

        let imageCandidate = makeCandidate(
            plainText: "#abc",
            urlString: "https://example.com",
            imageData: Data([1, 2, 3]),
            imageUTI: "public.png"
        )
        XCTAssertEqual(ClipboardClassifier.classify(imageCandidate)?.type, .image)

        let urlCandidate = makeCandidate(plainText: "#abc", urlString: "https://example.com")
        XCTAssertEqual(ClipboardClassifier.classify(urlCandidate)?.type, .url)

        let colorCandidate = makeCandidate(plainText: "#abc")
        XCTAssertEqual(ClipboardClassifier.classify(colorCandidate)?.type, .color)

        let textCandidate = makeCandidate(plainText: "ordinary text")
        XCTAssertEqual(ClipboardClassifier.classify(textCandidate)?.type, .text)
    }

    func testHexColorComponentsAcceptsOnlyFullValidHexColors() throws {
        let shorthand = try XCTUnwrap(ClipboardClassifier.hexColorComponents("#abc"))
        XCTAssertEqual(shorthand.r, 170.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(shorthand.g, 187.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(shorthand.b, 204.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(shorthand.a, 1.0, accuracy: 0.0001)

        let rgba = try XCTUnwrap(ClipboardClassifier.hexColorComponents("#aabbccdd"))
        XCTAssertEqual(rgba.r, 170.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(rgba.g, 187.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(rgba.b, 204.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(rgba.a, 221.0 / 255.0, accuracy: 0.0001)

        XCTAssertNotNil(ClipboardClassifier.hexColorComponents("#aabbcc"))
        XCTAssertEqual(ClipboardClassifier.classify(makeCandidate(plainText: "#abc"))?.type, .color)
        XCTAssertEqual(ClipboardClassifier.classify(makeCandidate(plainText: "#aabbcc"))?.type, .color)
        XCTAssertEqual(ClipboardClassifier.classify(makeCandidate(plainText: "#aabbccdd"))?.type, .color)
        XCTAssertNil(ClipboardClassifier.hexColorComponents("#ggg"))
        XCTAssertNil(ClipboardClassifier.hexColorComponents("x #fff y"))
        XCTAssertNil(ClipboardClassifier.hexColorComponents("#12345"))
        XCTAssertNotEqual(ClipboardClassifier.classify(makeCandidate(plainText: "#ggg"))?.type, .color)
        XCTAssertNotEqual(ClipboardClassifier.classify(makeCandidate(plainText: "x #fff y"))?.type, .color)
        XCTAssertNotEqual(ClipboardClassifier.classify(makeCandidate(plainText: "#12345"))?.type, .color)
    }

    func testPreviewCollapsesWhitespaceAndTruncatesTo512Characters() throws {
        let text = String(repeating: "word \n\t", count: 200)
        let classified = try XCTUnwrap(ClipboardClassifier.classify(makeCandidate(plainText: text)))

        XCTAssertLessThanOrEqual(classified.previewText.count, 512)
        XCTAssertFalse(classified.previewText.contains("\n"))
        XCTAssertFalse(classified.previewText.contains("\t"))
        XCTAssertFalse(classified.previewText.contains("  "))
    }

    func testLargeTextNeedsTextBlobAndKeepsFullTextOutOfInlineContent() throws {
        let largeText = String(repeating: "x", count: ClipboardClassifier.maxInlineTextBytes + 1)
        let classified = try XCTUnwrap(ClipboardClassifier.classify(makeCandidate(plainText: largeText)))

        XCTAssertEqual(classified.type, .text)
        XCTAssertTrue(classified.needsTextBlob)
        XCTAssertNil(classified.contentText)
        XCTAssertEqual(classified.largeText, largeText)
        XCTAssertEqual(classified.byteSize, Data(largeText.utf8).count)
    }

    func testURLMetadataIncludesDomain() throws {
        let classified = try XCTUnwrap(ClipboardClassifier.classify(makeCandidate(urlString: "https://sub.example.com/path?q=1")))
        let metadata = try metadataDictionary(from: classified)

        XCTAssertEqual(classified.type, .url)
        XCTAssertEqual(metadata["domain"] as? String, "sub.example.com")
    }

    func testClassifyEmptyCandidateReturnsNil() {
        XCTAssertNil(ClipboardClassifier.classify(makeCandidate()))
    }

    private func makeCandidate(
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
    ) -> CaptureCandidate {
        CaptureCandidate(
            plainText: plainText,
            hasRichText: hasRichText,
            urlString: urlString,
            filePaths: filePaths,
            imageData: imageData,
            imageUTI: imageUTI,
            imagePixelSize: imagePixelSize,
            rawTypes: rawTypes,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
    }

    private func metadataDictionary(from classified: ClassifiedCapture) throws -> [String: Any] {
        let json = try XCTUnwrap(classified.metadataJSON)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
