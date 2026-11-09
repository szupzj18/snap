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

    // MARK: Adjusting

    private let selection = CGRect(x: 100, y: 100, width: 200, height: 100)

    func testHandleHitTestingPrefersCorners() {
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 102, y: 198), of: selection), .topLeft)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 200, y: 101), of: selection), .bottom)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 297, y: 150), of: selection), .right)
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 200, y: 150), of: selection))
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 400, y: 400), of: selection))
    }

    func testResizeMovesOnlyThatHandlesEdges() {
        XCTAssertEqual(SelectionGeometry.resize(selection, handle: .right, by: CGVector(dx: 50, dy: 30), within: bounds),
                       CGRect(x: 100, y: 100, width: 250, height: 100))
        XCTAssertEqual(SelectionGeometry.resize(selection, handle: .topLeft, by: CGVector(dx: -10, dy: 20), within: bounds),
                       CGRect(x: 90, y: 100, width: 210, height: 120))
        // ⌥-arrow keys drag the bottom-right corner: ↓ makes it taller.
        XCTAssertEqual(SelectionGeometry.resize(selection, handle: .bottomRight, by: CGVector(dx: 1, dy: -1), within: bounds),
                       CGRect(x: 100, y: 99, width: 201, height: 101))
    }

    func testResizeStopsAtBoundsAndMinimum() {
        XCTAssertEqual(SelectionGeometry.resize(selection, handle: .left, by: CGVector(dx: -500, dy: 0), within: bounds),
                       CGRect(x: 0, y: 100, width: 300, height: 100))
        XCTAssertEqual(SelectionGeometry.resize(selection, handle: .left, by: CGVector(dx: 500, dy: 0), within: bounds, minimum: 4),
                       CGRect(x: 296, y: 100, width: 4, height: 100))
    }

    func testResizedKeepsTopLeftAndStaysInside() {
        XCTAssertEqual(SelectionGeometry.resized(selection, to: CGSize(width: 50, height: 40), within: bounds),
                       CGRect(x: 100, y: 160, width: 50, height: 40))
        // Too wide to keep its x: shifted left, never larger than the screen.
        XCTAssertEqual(SelectionGeometry.resized(selection, to: CGSize(width: 2000, height: 100), within: bounds),
                       CGRect(x: 0, y: 100, width: 1000, height: 100))
    }

    func testParseSize() {
        XCTAssertEqual(SelectionGeometry.parseSize("800x600")?.width, 800)
        XCTAssertEqual(SelectionGeometry.parseSize(" 800 × 600 ")?.height, 600)
        XCTAssertEqual(SelectionGeometry.parseSize("1280*720")?.width, 1280)
        XCTAssertEqual(SelectionGeometry.parseSize("640 480")?.height, 480)
        XCTAssertNil(SelectionGeometry.parseSize("800"))
        XCTAssertNil(SelectionGeometry.parseSize("0x600"))
        XCTAssertNil(SelectionGeometry.parseSize("abc x def"))
    }

    // MARK: Remembering

    func testViewRectFromGlobalFlipsWithinItsDisplay() {
        // A second display to the right of a 1000-wide main display, 800 tall.
        let display = CGRect(x: 1000, y: 0, width: 1440, height: 900)
        XCTAssertEqual(SelectionGeometry.viewRect(fromGlobal: CGRect(x: 1100, y: 50, width: 300, height: 200), displayFrame: display),
                       CGRect(x: 100, y: 650, width: 300, height: 200))
    }

    func testViewRectIsClippedOrDroppedWhenTheDisplayShrank() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(SelectionGeometry.viewRect(fromGlobal: CGRect(x: 700, y: 0, width: 300, height: 100), displayFrame: display),
                       CGRect(x: 700, y: 500, width: 100, height: 100))
        XCTAssertNil(SelectionGeometry.viewRect(fromGlobal: CGRect(x: 900, y: 0, width: 300, height: 100), displayFrame: display))
    }
}

