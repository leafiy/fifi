import Foundation
import XCTest
@testable import FifiCore

final class SettingsCodecTests: XCTestCase {
    func testSettingsExportRoundTripsCollectionsAndPrivacyRules() throws {
        let export = SettingsExport(
            settings: AppSettings(selectionBehavior: .copy, sortOrder: .mostUsed, fuzzyRanking: true),
            ignoredApps: [IgnoredApp(bundleID: "com.example.Ignore", appName: "Ignore Me")],
            ignoreRegexRules: [IgnoreRegexRule(id: 7, pattern: "secret", label: "Secrets", enabled: false)],
            appPrivacyRules: [AppPrivacyRule(bundleID: "com.example.Private", appName: "Private", mode: .memoryOnly)]
        )

        let decoded = try SettingsCodec.decode(try SettingsCodec.encode(export))

        XCTAssertEqual(decoded.version, export.version)
        XCTAssertEqual(decoded.settings, export.settings)
        XCTAssertEqual(decoded.ignoredApps, export.ignoredApps)
        XCTAssertEqual(decoded.ignoreRegexRules, export.ignoreRegexRules)
        XCTAssertEqual(decoded.appPrivacyRules, export.appPrivacyRules)
    }

    func testSettingsCodecRejectsUnsupportedFutureVersion() {
        let unsupported = Data("{\"version\":999,\"settings\":{}}".utf8)

        XCTAssertThrowsError(try SettingsCodec.decode(unsupported)) { error in
            guard case SettingsCodecError.unsupportedVersion(999) = error else {
                return XCTFail("Expected unsupportedVersion(999), got \(error)")
            }
        }
    }
}
