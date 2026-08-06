import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Fifi

@MainActor
final class PickerControllerTests: XCTestCase {
    func testBackspaceIsNotConsumedWhileEditingSearchText() {
        XCTAssertFalse(PickerController.shouldDeleteSelected(
            keyCode: kVK_Delete,
            modifiers: [],
            isEditingText: true
        ))
        XCTAssertFalse(PickerController.shouldDeleteSelected(
            keyCode: kVK_Delete,
            modifiers: .command,
            isEditingText: true
        ))
    }

    func testForwardDeleteIsNotConsumedWhileEditingSearchText() {
        XCTAssertFalse(PickerController.shouldDeleteSelected(
            keyCode: kVK_ForwardDelete,
            modifiers: [],
            isEditingText: true
        ))
    }

    func testBackspaceStillDeletesSelectionOutsideTextEditing() {
        XCTAssertTrue(PickerController.shouldDeleteSelected(
            keyCode: kVK_Delete,
            modifiers: [],
            isEditingText: false
        ))
    }
}
