import Foundation
import XCTest
@testable import FifiCore

final class ContentHashTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(
            ContentHash.sha256(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            ContentHash.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testDataAndStringOverloadsAgree() {
        let string = "Fifi clipboard history"

        XCTAssertEqual(ContentHash.sha256(string), ContentHash.sha256(Data(string.utf8)))
    }
}
