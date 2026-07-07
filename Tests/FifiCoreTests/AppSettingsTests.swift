import Foundation
import XCTest
@testable import FifiCore

final class AppSettingsTests: XCTestCase {
    func testDecodingLegacyPayloadWithoutAppLanguageMigratesToSystemLanguage() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"hotkeyShortcut":"ctrl+opt+space","selectionBehavior":"copy","maxHistoryCount":42,"retentionDays":7,"maxStorageMB":128,"launchAtLogin":true,"isRecordingPaused":true}"#.utf8
            )
        )

        XCTAssertEqual(settings.selectionBehavior, .copy)
        XCTAssertEqual(settings.hotkeyShortcut, "ctrl+opt+space")
        XCTAssertEqual(settings.appLanguage, "system")
        XCTAssertFalse(settings.quickShare.isConfigured)
        XCTAssertEqual(settings.quickShare.keyPrefix, "fifi")
    }

    func testEncodingRoundTripPreservesAppLanguage() throws {
        let settings = AppSettings(
            hotkeyShortcut: "ctrl+opt+space",
            selectionBehavior: .copy,
            maxHistoryCount: 42,
            retentionDays: 7,
            maxStorageMB: 128,
            launchAtLogin: true,
            isRecordingPaused: true,
            appLanguage: "zh-Hans"
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.appLanguage, "zh-Hans")
    }

    func testEncodingRoundTripPreservesQuickShareSettings() throws {
        let settings = AppSettings(
            quickShare: QuickShareSettings(
                provider: .aliyunOSS,
                endpointURL: "https://oss-cn-hangzhou.aliyuncs.com",
                region: "cn-hangzhou",
                bucket: "public-bucket",
                accessKeyID: "key",
                secretAccessKey: "secret",
                keyPrefix: "clips"
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.quickShare.provider, .aliyunOSS)
        XCTAssertEqual(decoded.quickShare.endpointURL, "https://oss-cn-hangzhou.aliyuncs.com")
        XCTAssertEqual(decoded.quickShare.region, "cn-hangzhou")
        XCTAssertEqual(decoded.quickShare.bucket, "public-bucket")
        XCTAssertEqual(decoded.quickShare.accessKeyID, "key")
        XCTAssertEqual(decoded.quickShare.secretAccessKey, "secret")
        XCTAssertEqual(decoded.quickShare.keyPrefix, "clips")
        XCTAssertTrue(decoded.quickShare.isConfigured)
    }
}
