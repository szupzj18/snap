import CoreGraphics
import XCTest
@testable import SnapAnnotate

final class AnnotationRendererTests: XCTestCase {
    func testExportKeepsOrientation() throws {
        // Top half red, bottom half blue.
        let base = Pixels.halves(width: 20, height: 20)
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export([]))
        XCTAssertEqual(Pixels.at(output, x: 5, y: 2), [255, 0, 0, 255])
        XCTAssertEqual(Pixels.at(output, x: 5, y: 17), [0, 0, 255, 255])
    }

    func testRectangleIsDrawnAtTopLeftCoordinates() throws {
        let base = Pixels.solid(width: 40, height: 40)
        let rect = Annotation(shape: .rectangle(CGRect(x: 10, y: 4, width: 20, height: 10)), color: .green, lineWidth: 2)
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export([rect]))
        // Middle of the top edge (y = 4) is green; the inside stays white.
        let edge = Pixels.at(output, x: 20, y: 4)
        XCTAssertLessThan(edge[0], 100)
        XCTAssertGreaterThan(edge[1], 150)
        XCTAssertEqual(Pixels.at(output, x: 20, y: 9), [255, 255, 255, 255])
    }

    func testPixelateFlattensDetailOnlyInsideRect() throws {
        let base = Pixels.stripes(width: 64, height: 64)
        let annotation = Annotation(shape: .pixelate(CGRect(x: 0, y: 0, width: 32, height: 32)), color: .red, lineWidth: 1)
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export([annotation]))
        // Neighboring stripes inside the rect end up the same color...
        XCTAssertEqual(Pixels.at(output, x: 2, y: 2), Pixels.at(output, x: 3, y: 2))
        // ...while outside they still alternate.
        XCTAssertNotEqual(Pixels.at(output, x: 40, y: 40), Pixels.at(output, x: 41, y: 40))
    }

    func testBlurSoftensInsideRect() throws {
        let base = Pixels.stripes(width: 64, height: 64)
        let annotation = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 32, height: 32)), color: .red, lineWidth: 1)
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export([annotation]))
        let pixel = Pixels.at(output, x: 10, y: 10)
        XCTAssertGreaterThan(pixel[0], 60)
        XCTAssertLessThan(pixel[0], 200)
    }

    func testHighlightTintsButKeepsContent() throws {
        let base = Pixels.solid(width: 20, height: 20)
        let annotation = Annotation(shape: .highlight(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .yellow, lineWidth: 1)
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export([annotation]))
        let tinted = Pixels.at(output, x: 5, y: 5)
        XCTAssertEqual(tinted[0], 255)
        XCTAssertLessThan(tinted[2], 255)
        XCTAssertEqual(Pixels.at(output, x: 15, y: 15), [255, 255, 255, 255])
    }

    func testTextAndCounterAndArrowPaintPixels() throws {
        let base = Pixels.solid(width: 200, height: 100)
        let annotations = [
            Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "Hi", fontSize: 30), color: .red, lineWidth: 1),
            Annotation(shape: .counter(center: CGPoint(x: 150, y: 50), number: 1, radius: 20), color: .blue, lineWidth: 1),
            Annotation(shape: .arrow(from: CGPoint(x: 20, y: 90), to: CGPoint(x: 120, y: 90)), color: .red, lineWidth: 4),
        ]
        let output = try XCTUnwrap(AnnotationRenderer(base: base, scale: 1).export(annotations))
        XCTAssertTrue(Pixels.region(output, CGRect(x: 10, y: 10, width: 40, height: 35)).contains { $0[1] < 100 }, "text")
        XCTAssertLessThan(Pixels.at(output, x: 150, y: 35)[0], 50, "counter fill")
        XCTAssertLessThan(Pixels.at(output, x: 70, y: 90)[1], 100, "arrow shaft")
    }
}

enum Pixels {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func solid(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Red on top, blue on the bottom.
    static func halves(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }

    /// One-pixel black and white vertical stripes.
    static func stripes(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height)
        for x in 0..<width {
            let value: CGFloat = x.isMultiple(of: 2) ? 0 : 1
            context.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y), counted from the top-left.
    static func at(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        region(image, CGRect(x: x, y: y, width: 1, height: 1))[0]
    }

    static func region(_ image: CGImage, _ rect: CGRect) -> [[UInt8]] {
        let width = Int(rect.width)
        let height = Int(rect.height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -rect.minX, y: rect.maxY - CGFloat(image.height),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return stride(from: 0, to: data.count, by: 4).map { Array(data[$0..<$0 + 4]) }
    }
}
