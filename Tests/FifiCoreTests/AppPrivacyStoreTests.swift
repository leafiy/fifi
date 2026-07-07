import Foundation
import XCTest
@testable import FifiCore

final class AppPrivacyStoreTests: FifiCoreTestCase {
    func testSetRuleUpsertsAndRemoveDeletesRule() throws {
        let (database, _) = try makeStore()
        let store = AppPrivacyStore(database: database)

        try store.setRule(bundleID: "com.example.App", appName: "Example", mode: .sensitive)
        XCTAssertEqual(
            try store.rules(),
            [AppPrivacyRule(bundleID: "com.example.App", appName: "Example", mode: .sensitive)]
        )

        try store.setRule(bundleID: "com.example.App", appName: "Example Updated", mode: .memoryOnly)
        XCTAssertEqual(
            try store.rules(),
            [AppPrivacyRule(bundleID: "com.example.App", appName: "Example Updated", mode: .memoryOnly)]
        )

        try store.removeRule(bundleID: "com.example.App")
        XCTAssertTrue(try store.rules().isEmpty)
    }
}
