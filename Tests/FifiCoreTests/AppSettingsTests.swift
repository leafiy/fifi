import Foundation
import XCTest
import LeafiyUICore
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
        XCTAssertTrue(settings.showDockIcon)
    }

    func testEncodingRoundTripPreservesAppLanguage() throws {
        let settings = AppSettings(
            hotkeyShortcut: "ctrl+opt+space",
            selectionBehavior: .copy,
            maxHistoryCount: 42,
            retentionDays: 7,
            maxStorageMB: 128,
            launchAtLogin: true,
            showDockIcon: false,
            isRecordingPaused: true,
            appLanguage: "zh-Hans"
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.appLanguage, "zh-Hans")
        XCTAssertFalse(decoded.showDockIcon)
    }

    func testEncodingRoundTripPreservesQuickShareSettings() throws {
        let settings = AppSettings(
            quickShare: QuickShareSettings(
                provider: .s3,
                endpointURL: "https://oss-cn-hangzhou.aliyuncs.com",
                region: "cn-hangzhou",
                bucket: "public-bucket",
                keyPrefix: "clips",
                accessKeyID: "key",
                secretAccessKey: "secret"
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.quickShare.provider, .s3)
        XCTAssertEqual(decoded.quickShare.endpointURL, "https://oss-cn-hangzhou.aliyuncs.com")
        XCTAssertEqual(decoded.quickShare.region, "cn-hangzhou")
        XCTAssertEqual(decoded.quickShare.bucket, "public-bucket")
        XCTAssertEqual(decoded.quickShare.accessKeyID, "key")
        XCTAssertEqual(decoded.quickShare.secretAccessKey, "secret")
        XCTAssertEqual(decoded.quickShare.keyPrefix, "clips")
        XCTAssertTrue(decoded.quickShare.isConfigured)
    }

    func testWindowOpacityDefaultsOffAndOpaque() {
        let settings = AppSettings.defaults

        XCTAssertFalse(settings.windowOpacityEnabled)
        XCTAssertEqual(settings.windowOpacity, AppSettings.defaultWindowOpacity)
        XCTAssertEqual(settings.currentWindowOpacity, 1)
        XCTAssertEqual(settings.windowBlurIntensity, 0)
    }

    func testWindowOpacityIsClampedOnInitAndDecode() throws {
        XCTAssertEqual(AppSettings(windowOpacity: 0).windowOpacity, AppSettings.minWindowOpacity)
        XCTAssertEqual(AppSettings(windowOpacity: 2).windowOpacity, 1)
        XCTAssertEqual(AppSettings(windowOpacity: .nan).windowOpacity, AppSettings.defaultWindowOpacity)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"windowOpacityEnabled":true,"windowOpacity":0.01}"#.utf8)
        )
        XCTAssertTrue(decoded.windowOpacityEnabled)
        XCTAssertEqual(decoded.windowOpacity, AppSettings.minWindowOpacity)
    }

    func testDecodingLegacyPayloadWithoutOpacityKeysFallsBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"hotkeyShortcut":"cmd+shift+v"}"#.utf8)
        )

        XCTAssertFalse(decoded.windowOpacityEnabled)
        XCTAssertEqual(decoded.windowOpacity, AppSettings.defaultWindowOpacity)
    }

    func testWindowBlurDerivation() {
        XCTAssertEqual(AppSettings.windowBlur(forOpacity: 1), 0)
        XCTAssertEqual(
            AppSettings.windowBlur(forOpacity: AppSettings.minWindowOpacity),
            AppSettings.maxWindowBlur,
            accuracy: 0.0001
        )

        var settings = AppSettings(windowOpacityEnabled: true, windowOpacity: 0.55)
        XCTAssertEqual(settings.currentWindowOpacity, 0.55)
        XCTAssertEqual(
            settings.windowBlurIntensity,
            AppSettings.windowBlur(forOpacity: 0.55),
            accuracy: 0.0001
        )

        settings.windowOpacityEnabled = false
        XCTAssertEqual(settings.windowBlurIntensity, 0)
    }
}
