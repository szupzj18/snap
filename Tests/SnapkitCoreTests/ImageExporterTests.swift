import CoreGraphics
import ImageIO
import XCTest
@testable import SnapkitCore

final class ImageExporterTests: XCTestCase {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testPNGCarriesRetinaDPI() throws {
        let data = try ImageExporter.pngData(makeImage(width: 40, height: 20), scale: 2)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(properties[kCGImagePropertyDPIWidth] as? Double, 144)
    }

    func testWriteDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = makeImage(width: 4, height: 4)
        let first = try ImageExporter.writePNG(image, scale: 1, to: directory, filename: "Shot")
        let second = try ImageExporter.writePNG(image, scale: 1, to: directory, filename: "Shot")
        XCTAssertEqual(first.lastPathComponent, "Shot.png")
        XCTAssertEqual(second.lastPathComponent, "Shot (2).png")
    }
}
