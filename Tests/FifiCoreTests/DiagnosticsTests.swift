import XCTest
import LeafiyUICore
@testable import FifiCore

final class DiagnosticsTests: FifiCoreTestCase {
    func testCollectRedactsQuickShareCredentials() throws {
        let (database, historyStore) = try makeStore()
        let blobStore = try makeBlobStore()
        let settings = AppSettings(
            quickShare: QuickShareSettings(
                provider: .s3,
                endpointURL: "https://objects.example.test",
                region: "us-east-1",
                bucket: "private-bucket",
                accessKeyID: "AKIA_DIAGNOSTICS_SECRET",
                secretAccessKey: "super-secret-value"
            )
        )

        let report = Diagnostics.collect(
            database: database,
            historyStore: historyStore,
            blobStore: blobStore,
            settings: settings,
            appVersion: "test",
            databasePath: "/path/that/does/not/exist"
        )

        XCTAssertFalse(report.settingsJSON.contains("AKIA_DIAGNOSTICS_SECRET"))
        XCTAssertFalse(report.settingsJSON.contains("super-secret-value"))
        XCTAssertTrue(report.settingsJSON.contains("private-bucket"))
    }
}
