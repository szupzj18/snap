import XCTest
@testable import SnapCore

final class KeyNudgeTests: XCTestCase {
    func testArrowKeysMoveOnePointOrTenWithShift() {
        XCTAssertEqual(KeyNudge.offset(keyCode: 123, shift: false), CGVector(dx: -1, dy: 0))
        XCTAssertEqual(KeyNudge.offset(keyCode: 124, shift: true), CGVector(dx: 10, dy: 0))
        // AppKit's y grows up: ↑ is +y.
        XCTAssertEqual(KeyNudge.offset(keyCode: 126, shift: false), CGVector(dx: 0, dy: 1))
        XCTAssertEqual(KeyNudge.offset(keyCode: 125, shift: true), CGVector(dx: 0, dy: -10))
    }

    func testOtherKeysDoNothing() {
        XCTAssertNil(KeyNudge.offset(keyCode: 53, shift: false)) // Esc
        XCTAssertNil(KeyNudge.offset(keyCode: 0, shift: true)) // A
    }
}
