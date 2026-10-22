import CoreGraphics
import XCTest
@testable import SnapkitCore

final class ScreenGeometryTests: XCTestCase {
    func testFlipRectIsItsOwnInverse() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flipped = ScreenGeometry.flip(rect, primaryScreenHeight: 1080)
        XCTAssertEqual(flipped, CGRect(x: 10, y: 860, width: 300, height: 200))
        XCTAssertEqual(ScreenGeometry.flip(flipped, primaryScreenHeight: 1080), rect)
    }

    func testFlipRectOnSecondaryDisplayAbovePrimary() {
        // A display stacked above a 1080pt-high primary has negative Quartz y.
        let appKit = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        XCTAssertEqual(ScreenGeometry.flip(appKit, primaryScreenHeight: 1080), CGRect(x: 0, y: -1200, width: 1920, height: 1200))
    }

    func testPixelRectFlipsAndScales() {
        // 100x50pt selection at the bottom-left corner of a 1440x900pt Retina screen.
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let pixels = ScreenGeometry.pixelRect(fromBottomLeft: rect, in: CGSize(width: 1440, height: 900), scale: 2)
        XCTAssertEqual(pixels, CGRect(x: 0, y: 1700, width: 200, height: 100))
    }

    func testPixelRectSnapsOutwardToWholePixels() {
        let rect = CGRect(x: 10.3, y: 10.3, width: 20.2, height: 20.2)
        let pixels = ScreenGeometry.pixelRect(fromBottomLeft: rect, in: CGSize(width: 100, height: 100), scale: 1)
        XCTAssertEqual(pixels, CGRect(x: 10, y: 69, width: 21, height: 21))
    }

    func testPixelRectIsClampedToImage() {
        let rect = CGRect(x: -10, y: -10, width: 50, height: 50)
        let pixels = ScreenGeometry.pixelRect(fromBottomLeft: rect, in: CGSize(width: 100, height: 100), scale: 2)
        XCTAssertEqual(pixels, CGRect(x: 0, y: 120, width: 80, height: 80))
    }
}
