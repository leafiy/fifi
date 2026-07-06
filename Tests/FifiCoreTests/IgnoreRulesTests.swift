import Foundation
import XCTest
@testable import FifiCore

final class IgnoreRulesTests: FifiCoreTestCase {
    func testStoreCRUDRoundTripsIgnoredAppsAndRegexRules() throws {
        let (database, _) = try makeStore()
        let store = IgnoreRulesStore(database: database)

        try store.addIgnoredApp(bundleID: "com.example.Secret", appName: "Secret App")
        var apps = try store.ignoredApps()
        let app = try XCTUnwrap(apps.first { $0.bundleID == "com.example.Secret" })
        XCTAssertEqual(app.appName, "Secret App")

        let rule = try store.addRegexRule(pattern: "password", label: "Passwords")
        var rules = try store.regexRules()
        let storedRule = try XCTUnwrap(rules.first { $0.id == rule.id })
        XCTAssertEqual(storedRule.pattern, "password")
        XCTAssertEqual(storedRule.label, "Passwords")
        XCTAssertTrue(storedRule.enabled)

        try store.setRegexRule(id: rule.id, enabled: false)
        rules = try store.regexRules()
        XCTAssertFalse(try XCTUnwrap(rules.first { $0.id == rule.id }).enabled)

        try store.removeRegexRule(id: rule.id)
        XCTAssertFalse(try store.regexRules().contains { $0.id == rule.id })

        try store.removeIgnoredApp(bundleID: "com.example.Secret")
        apps = try store.ignoredApps()
        XCTAssertFalse(apps.contains { $0.bundleID == "com.example.Secret" })
    }

    func testEvaluatorMatchesBundleIDExactly() {
        let evaluator = IgnoreRuleEvaluator(ignoredBundleIDs: ["com.example.Secret"], regexRules: [])

        XCTAssertTrue(evaluator.shouldIgnore(bundleID: "com.example.Secret"))
        XCTAssertFalse(evaluator.shouldIgnore(bundleID: "com.example.Secret.Helper"))
        XCTAssertFalse(evaluator.shouldIgnore(bundleID: "com.example"))
        XCTAssertFalse(evaluator.shouldIgnore(bundleID: nil))
    }

    func testEvaluatorUsesCaseInsensitiveSubstringRegexAndSkipsDisabledOrInvalidRules() throws {
        let (database, _) = try makeStore()
        let store = IgnoreRulesStore(database: database)
        _ = try store.addRegexRule(pattern: "secret\\s+code", label: "Secret")
        let disabled = try store.addRegexRule(pattern: "disabled", label: "Disabled")
        _ = try store.addRegexRule(pattern: "(", label: "Invalid")
        try store.setRegexRule(id: disabled.id, enabled: false)

        let evaluator = IgnoreRuleEvaluator(ignoredBundleIDs: [], regexRules: try store.regexRules())

        XCTAssertTrue(evaluator.shouldIgnore(text: "The SECRET   code is here"))
        XCTAssertFalse(evaluator.shouldIgnore(text: "this mentions disabled only"))
        XCTAssertFalse(evaluator.shouldIgnore(text: "ordinary text"))
        XCTAssertFalse(evaluator.shouldIgnore(text: nil))
    }
}
