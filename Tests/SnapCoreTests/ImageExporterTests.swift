import CoreGraphics
import ImageIO
import XCTest
@testable import SnapCore

final class ImageExporterTests: XCTestCase {
    func testPNGCarriesRetinaDPI() throws {
        let data = try ImageExporter.pngData(TestImage.solid(width: 40, height: 20), scale: 2)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(properties[kCGImagePropertyDPIWidth] as? Double, 144)
    }

    func testWriteDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = TestImage.solid(width: 4, height: 4)
        let first = try ImageExporter.writePNG(image, scale: 1, to: directory, filename: "Shot")
        let second = try ImageExporter.writePNG(image, scale: 1, to: directory, filename: "Shot")
        XCTAssertEqual(first.lastPathComponent, "Shot.png")
        XCTAssertEqual(second.lastPathComponent, "Shot (2).png")
    }
}
