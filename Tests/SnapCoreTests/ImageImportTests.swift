import AppKit
import XCTest
@testable import SnapCore

final class ImageImportTests: XCTestCase {
    func testFileKeepsRetinaScaleFromDPI() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try ImageExporter.writePNG(TestImage.solid(width: 40, height: 20, red: 1), scale: 2, to: directory, filename: "shot")
        let capture = try ImageImport.capture(fromFile: url)
        XCTAssertEqual(capture.image.width, 40)
        XCTAssertEqual(capture.scale, 2)
        XCTAssertEqual(capture.pointSize, CGSize(width: 20, height: 10))
    }

    func testUnreadableFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: url.path, contents: Data("not an image".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ImageImport.capture(fromFile: url))
    }

    func testPasteboardImageDataAndFiles() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SnapTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertFalse(ImageImport.pasteboardHasImage(pasteboard))

        pasteboard.clearContents()
        pasteboard.setData(try ImageExporter.pngData(TestImage.solid(width: 8, height: 6), scale: 1), forType: .png)
        XCTAssertTrue(ImageImport.pasteboardHasImage(pasteboard))
        XCTAssertEqual(ImageImport.capture(from: pasteboard)?.image.width, 8)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try ImageExporter.writePNG(TestImage.solid(width: 12, height: 6), scale: 1, to: directory, filename: "copied")
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        XCTAssertTrue(ImageImport.pasteboardHasImage(pasteboard))
        XCTAssertEqual(ImageImport.capture(from: pasteboard)?.image.width, 12)
    }

    func testScaleFromDPI() {
        XCTAssertEqual(ImageImport.scale(fromDPI: nil), 1)
        XCTAssertEqual(ImageImport.scale(fromDPI: 72), 1)
        XCTAssertEqual(ImageImport.scale(fromDPI: 144), 2)
        XCTAssertEqual(ImageImport.scale(fromDPI: 300), 3)
    }
}
