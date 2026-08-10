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
        XCTAssertEqual(settings.applicationIconMode, .menuBar)
    }

    func testEncodingRoundTripPreservesAppLanguage() throws {
        let settings = AppSettings(
            hotkeyShortcut: "ctrl+opt+space",
            selectionBehavior: .copy,
            maxHistoryCount: 42,
            retentionDays: 7,
            maxStorageMB: 128,
            launchAtLogin: true,
            applicationIconMode: .dock,
            isRecordingPaused: true,
            appLanguage: "zh-Hans"
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.appLanguage, "zh-Hans")
        XCTAssertEqual(decoded.applicationIconMode, .dock)
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
        XCTAssertEqual(settings.currentWindowOpacity, 1)
        XCTAssertEqual(settings.windowBlurIntensity, 0)
    }

    func testWindowOpacityToggleUsesFixedLevels() {
        let settings = AppSettings(windowOpacityEnabled: true)

        XCTAssertEqual(settings.currentWindowOpacity, 0.94)
        XCTAssertEqual(settings.currentWindowOpacity, AppSettings.fixedWindowOpacity)
        XCTAssertEqual(settings.windowBlurIntensity, 0.8)
        XCTAssertEqual(settings.windowBlurIntensity, AppSettings.fixedWindowBlur)
    }

    func testDecodingLegacySliderPayloadKeepsToggleAndIgnoresLevel() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"windowOpacityEnabled":true,"windowOpacity":0.4}"#.utf8)
        )

        XCTAssertTrue(decoded.windowOpacityEnabled)
        XCTAssertEqual(decoded.currentWindowOpacity, AppSettings.fixedWindowOpacity)
    }

    func testDecodingPayloadWithoutOpacityKeyDefaultsOff() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"hotkeyShortcut":"cmd+shift+v"}"#.utf8)
        )

        XCTAssertFalse(decoded.windowOpacityEnabled)
        XCTAssertEqual(decoded.windowBlurIntensity, 0)
    }

    func testDetailTogglesDefaultOn() {
        let settings = AppSettings.defaults

        XCTAssertTrue(settings.showSourceApp)
        XCTAssertTrue(settings.showItemSize)
        XCTAssertTrue(settings.showItemTime)
        XCTAssertTrue(settings.showImageResolution)
    }
}
