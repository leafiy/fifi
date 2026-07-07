import Foundation
import XCTest
@testable import FifiCore

final class SettingsCodableTests: XCTestCase {
    func testAppSettingsDecodesMissingKeysAndPreservesPresentV1Keys() throws {
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(empty)), empty)

        let data = Data(
            """
            {
              "hotkeyShortcut": "ctrl+space",
              "selectionBehavior": "copy",
              "maxHistoryCount": 25,
              "retentionDays": 7,
              "maxStorageMB": 128,
              "launchAtLogin": true,
              "isRecordingPaused": true
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.hotkeyShortcut, "ctrl+space")
        XCTAssertEqual(decoded.selectionBehavior, .copy)
        XCTAssertEqual(decoded.maxHistoryCount, 25)
        XCTAssertEqual(decoded.retentionDays, 7)
        XCTAssertEqual(decoded.maxStorageMB, 128)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertTrue(decoded.isRecordingPaused)
        XCTAssertFalse(decoded.showPreviewPanel)
        XCTAssertFalse(decoded.showPickerFilters)
        XCTAssertTrue(decoded.showSourceApp)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decoded)), decoded)
    }

    func testAppSettingsEncodeDecodeRoundTripsAllFields() throws {
        let settings = AppSettings(
            hotkeyShortcut: "cmd+option+v",
            selectionBehavior: .copy,
            maxHistoryCount: 123,
            retentionDays: 14,
            maxStorageMB: 64,
            launchAtLogin: true,
            isRecordingPaused: true,
            appearance: .dark,
            rowDensity: .compact,
            pickerWidth: 640,
            pickerHeight: 720,
            showPreviewPanel: true,
            showPickerFilters: true,
            showSourceApp: false,
            numberShortcuts: false,
            sortOrder: .mostUsed,
            fuzzyRanking: true,
            privacy: PrivacySettings(
                skipConcealed: false,
                detectCreditCards: true,
                detectAPIKeys: true,
                detectVerificationCodes: true,
                handling: .ignore,
                autoDeleteSeconds: 15,
                privateMode: true,
                encryptBlobs: true
            )
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testPrivacySettingsDecodesMissingKeysAndRoundTripsAllFields() throws {
        let empty = try JSONDecoder().decode(PrivacySettings.self, from: Data("{}".utf8))
        XCTAssertEqual(try JSONDecoder().decode(PrivacySettings.self, from: JSONEncoder().encode(empty)), empty)

        let partial = try JSONDecoder().decode(
            PrivacySettings.self,
            from: Data("{\"skipConcealed\":false,\"detectCreditCards\":true}".utf8)
        )
        XCTAssertFalse(partial.skipConcealed)
        XCTAssertTrue(partial.detectCreditCards)
        XCTAssertEqual(try JSONDecoder().decode(PrivacySettings.self, from: JSONEncoder().encode(partial)), partial)

        let settings = PrivacySettings(
            skipConcealed: false,
            detectCreditCards: true,
            detectAPIKeys: true,
            detectVerificationCodes: true,
            handling: .ignore,
            autoDeleteSeconds: 9,
            privateMode: true,
            encryptBlobs: true
        )
        let data = try JSONEncoder().encode(settings)

        XCTAssertEqual(try JSONDecoder().decode(PrivacySettings.self, from: data), settings)
    }

}
