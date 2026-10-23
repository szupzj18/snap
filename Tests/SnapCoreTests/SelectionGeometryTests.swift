import CoreGraphics
import XCTest
@testable import SnapCore

final class SelectionGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func rect(_ anchor: CGPoint, _ current: CGPoint, square: Bool = false, fromCenter: Bool = false) -> CGRect {
        SelectionGeometry.rect(anchor: anchor, current: current, square: square, fromCenter: fromCenter, bounds: bounds)
    }

    func testPlainDragInAnyDirection() {
        XCTAssertEqual(rect(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250)), CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(rect(CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 100)), CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testSquareFollowsLongerSideAndDirection() {
        XCTAssertEqual(rect(CGPoint(x: 500, y: 500), CGPoint(x: 400, y: 530), square: true),
                       CGRect(x: 400, y: 500, width: 100, height: 100))
    }

    func testFromCenterGrowsBothWays() {
        XCTAssertEqual(rect(CGPoint(x: 500, y: 400), CGPoint(x: 560, y: 380), fromCenter: true),
                       CGRect(x: 440, y: 380, width: 120, height: 40))
    }

    func testSquareFromCenter() {
        XCTAssertEqual(rect(CGPoint(x: 500, y: 400), CGPoint(x: 510, y: 450), square: true, fromCenter: true),
                       CGRect(x: 450, y: 350, width: 100, height: 100))
    }

    func testClippedToBounds() {
        XCTAssertEqual(rect(CGPoint(x: 50, y: 50), CGPoint(x: 70, y: 70), fromCenter: true),
                       CGRect(x: 30, y: 30, width: 40, height: 40))
        XCTAssertEqual(rect(CGPoint(x: 950, y: 50), CGPoint(x: 1100, y: 100)), CGRect(x: 950, y: 50, width: 50, height: 50))
    }

    func testMoveKeepsSizeAtEdges() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(SelectionGeometry.move(selection, by: CGVector(dx: 30, dy: -20), within: bounds),
                       CGRect(x: 130, y: 80, width: 200, height: 100))
        XCTAssertEqual(SelectionGeometry.move(selection, by: CGVector(dx: -500, dy: 2000), within: bounds),
                       CGRect(x: 0, y: 700, width: 200, height: 100))
    }
}
