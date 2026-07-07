import Foundation
import XCTest
@testable import FifiCore

final class URLCleanerTests: XCTestCase {
    func testCleanedStripsTrackingParametersButKeepsOtherParametersFragmentAndOrder() {
        let input = "https://example.com/path?keep=1&utm_source=newsletter&b=2&fbclid=abc#section"

        XCTAssertEqual(URLCleaner.cleaned(input), "https://example.com/path?keep=1&b=2#section")
    }

    func testCleanedDropsQuestionMarkWhenAllParametersAreRemoved() {
        XCTAssertEqual(URLCleaner.cleaned("https://example.com/path?utm_medium=email&gclid=abc"), "https://example.com/path")
    }

    func testCleanedRejectsNonHTTPURLsAndMalformedStrings() {
        XCTAssertNil(URLCleaner.cleaned("not a url"))
        XCTAssertNil(URLCleaner.cleaned("ftp://example.com/path?utm_source=x"))
    }

    func testYouTubeSiParameterIsTrackingButNonYouTubeSiIsKept() {
        XCTAssertEqual(URLCleaner.cleaned("https://www.youtube.com/watch?v=abc&si=share"), "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(URLCleaner.cleaned("https://example.com/path?si=share&keep=1"), "https://example.com/path?si=share&keep=1")
    }

    func testHasTrackingParametersReflectsWhetherCleanerWouldRemoveAnything() {
        XCTAssertTrue(URLCleaner.hasTrackingParameters("https://example.com/path?utm_campaign=sale&keep=1"))
        XCTAssertTrue(URLCleaner.hasTrackingParameters("https://youtu.be/abc?si=share"))
        XCTAssertFalse(URLCleaner.hasTrackingParameters("https://example.com/path?si=share&keep=1"))
        XCTAssertFalse(URLCleaner.hasTrackingParameters("not a url"))
    }
}
