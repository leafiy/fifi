import Foundation
import XCTest
import FifiCore
import LeafiyUICore
@testable import Fifi

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testSharedStoreRoundTripPersistsPlaintextQuickShareCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: fileURL)
        var settings = AppSettings.defaults
        settings.appLanguage = "zh-Hans"
        settings.quickShare = QuickShareSettings(
            provider: .s3,
            endpointURL: "https://oss-cn-hangzhou.aliyuncs.com",
            region: "cn-hangzhou",
            bucket: "public-bucket",
            keyPrefix: "clips",
            accessKeyID: "plain-access-key",
            secretAccessKey: "plain-secret-key"
        )

        try store.save(settings)

        let data = try Data(contentsOf: fileURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let quickShare = try XCTUnwrap(payload["quickShare"] as? [String: Any])
        XCTAssertEqual(quickShare["accessKeyID"] as? String, "plain-access-key")
        XCTAssertEqual(quickShare["secretAccessKey"] as? String, "plain-secret-key")

        let loaded = SettingsStore(fileURL: fileURL).load()
        XCTAssertEqual(loaded, settings)

        let sanitized = store.sanitizedSettings()
        XCTAssertEqual(sanitized.quickShare.accessKeyID, "")
        XCTAssertEqual(sanitized.quickShare.secretAccessKey, "")
        XCTAssertEqual(store.load().quickShare.accessKeyID, "plain-access-key")
        XCTAssertEqual(store.load().quickShare.secretAccessKey, "plain-secret-key")
    }
}
