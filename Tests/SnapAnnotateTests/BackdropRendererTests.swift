import CoreGraphics
import XCTest
@testable import SnapAnnotate

final class BackdropRendererTests: XCTestCase {
    func testPaddingAddsAroundAtScale() {
        let layout = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 200),
                                             backdrop: Backdrop(isEnabled: true, padding: 50), scale: 2)
        XCTAssertEqual(layout.canvasSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(layout.contentRect, CGRect(x: 100, y: 100, width: 400, height: 200))
    }

    func testAspectGrowsShortSideAndCenters() {
        let wide = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 400),
                                           backdrop: Backdrop(isEnabled: true, padding: 0, aspect: .wide), scale: 1)
        XCTAssertEqual(wide.canvasSize, CGSize(width: 711, height: 400))
        XCTAssertEqual(wide.contentRect.minX, 156)

        let square = BackdropRenderer.layout(contentSize: CGSize(width: 800, height: 200),
                                             backdrop: Backdrop(isEnabled: true, padding: 0, aspect: .square), scale: 1)
        XCTAssertEqual(square.canvasSize, CGSize(width: 800, height: 800))
        XCTAssertEqual(square.contentRect.minY, 300)
    }

    func testComposeFillsBackgroundAndKeepsContent() throws {
        let content = Pixels.solid(width: 100, height: 60)
        let backdrop = Backdrop(isEnabled: true, fill: .solid(RGBA(0, 0, 1)), padding: 20, cornerRadius: 0, shadow: 0)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(output.width, 140)
        XCTAssertEqual(output.height, 100)
        XCTAssertEqual(Pixels.at(output, x: 5, y: 5), [0, 0, 255, 255], "background")
        XCTAssertEqual(Pixels.at(output, x: 70, y: 50), [255, 255, 255, 255], "screenshot")
    }

    func testRoundedCornersShowTheBackground() throws {
        let content = Pixels.solid(width: 100, height: 100)
        let backdrop = Backdrop(isEnabled: true, fill: .solid(RGBA(0, 0, 0)), padding: 10, cornerRadius: 20, shadow: 0)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(Pixels.at(output, x: 11, y: 11), [0, 0, 0, 255], "corner rounded off")
        XCTAssertEqual(Pixels.at(output, x: 60, y: 11), [255, 255, 255, 255], "edge middle kept")
    }

    func testClearFillLeavesTransparencyWithShadow() throws {
        let content = Pixels.solid(width: 100, height: 100)
        let backdrop = Backdrop(isEnabled: true, fill: .clear, padding: 40, cornerRadius: 0, shadow: 1)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(Pixels.at(output, x: 0, y: 0)[3], 0, "far corner transparent")
        XCTAssertGreaterThan(Pixels.at(output, x: 90, y: 145)[3], 0, "shadow below the screenshot")
    }
}
