import Foundation
import XCTest
@testable import FifiCore

final class ColorValueTests: XCTestCase {
    func testOpaqueHexFormatsAsHexRGBAndHSL() throws {
        let color = try XCTUnwrap(ColorValue(hexString: "#FF5733"))

        XCTAssertEqual(color.hexString, "#FF5733")
        XCTAssertEqual(color.rgbString, "rgb(255, 87, 51)")
        XCTAssertEqual(color.hslString, "hsl(11, 100%, 60%)")
    }

    func testAlphaHexFormatsAsEightDigitHexRGBAAndHSLA() throws {
        let color = try XCTUnwrap(ColorValue(hexString: "#FF5733CC"))

        XCTAssertEqual(color.hexString, "#FF5733CC")
        XCTAssertEqual(color.rgbString, "rgba(255, 87, 51, 0.80)")
        XCTAssertEqual(color.hslString, "hsla(11, 100%, 60%, 0.80)")
    }

    func testInvalidHexStringIsRejected() {
        XCTAssertNil(ColorValue(hexString: "#GG5733"))
        XCTAssertNil(ColorValue(hexString: "#12345"))
    }
}
