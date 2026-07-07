import Foundation
import XCTest
@testable import FifiCore

final class FuzzyScorerTests: XCTestCase {
    func testScoreReturnsValueOnlyForNonEmptySubsequenceMatches() {
        XCTAssertNotNil(FuzzyScorer.score(query: "fifi", candidate: "FifiCore file"))
        XCTAssertNil(FuzzyScorer.score(query: "xyz", candidate: "abc"))
        XCTAssertNil(FuzzyScorer.score(query: "", candidate: "FifiCore file"))
        XCTAssertNil(FuzzyScorer.score(query: "longer", candidate: "tiny"))
    }

    func testWordStartContiguousMatchScoresHigherThanMidWordScatteredMatch() throws {
        let wordStart = try XCTUnwrap(FuzzyScorer.score(query: "fi", candidate: "FifiCore file"))
        let scattered = try XCTUnwrap(FuzzyScorer.score(query: "fi", candidate: "safe inside"))

        XCTAssertGreaterThan(wordStart, scattered)
    }
}
