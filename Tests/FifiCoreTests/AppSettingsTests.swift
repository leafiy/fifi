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
}
