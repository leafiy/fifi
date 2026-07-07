import Foundation
import XCTest
@testable import FifiCore

final class SensitiveContentTests: XCTestCase {
    func testDetectsValidCreditCardButRejectsAllSameDigitRuns() {
        let options = SensitiveDetectionOptions(detectCreditCards: true)

        XCTAssertEqual(SensitiveContentDetector.detect(in: "card 4111 1111 1111 1111", options: options), .creditCard)
        XCTAssertNil(SensitiveContentDetector.detect(in: "1111 1111 1111 1111", options: options))
    }

    func testDetectsKnownAPIKeyShapesAndCredentialAssignments() {
        let options = SensitiveDetectionOptions(detectAPIKeys: true)

        XCTAssertEqual(SensitiveContentDetector.detect(in: "token ghp_abcdefghijklmnopqrstuvwx", options: options), .apiKey)
        XCTAssertEqual(SensitiveContentDetector.detect(in: "AKIAABCDEFGHIJKLMNOP", options: options), .apiKey)
        XCTAssertEqual(SensitiveContentDetector.detect(in: "password: hunter2xy", options: options), .apiKey)
    }

    func testDetectsVerificationCodesWithKeywordOrWholeText() {
        let options = SensitiveDetectionOptions(detectVerificationCodes: true)

        XCTAssertEqual(SensitiveContentDetector.detect(in: "Your verification code is 482913", options: options), .verificationCode)
        XCTAssertEqual(SensitiveContentDetector.detect(in: "123456", options: options), .verificationCode)
    }

    func testDisabledOptionsAndOversizedTextDoNotDetect() {
        XCTAssertNil(SensitiveContentDetector.detect(in: "password: hunter2xy", options: .allOff))
        XCTAssertNil(SensitiveContentDetector.detect(in: String(repeating: "a", count: 4_097) + " password: hunter2xy", options: SensitiveDetectionOptions(detectAPIKeys: true)))
    }
}
