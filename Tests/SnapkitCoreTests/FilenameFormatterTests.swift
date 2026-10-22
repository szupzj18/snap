import XCTest
@testable import SnapkitCore

final class FilenameFormatterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-10-22 15:04:05 UTC
    private let date = Date(timeIntervalSince1970: 1_792_681_445)

    func testDefaultTemplate() {
        let name = FilenameFormatter.filename(template: FilenameFormatter.defaultTemplate, date: date, mode: .area, timeZone: utc)
        XCTAssertEqual(name, "Snapkit 2026-10-22 at 15.04.05")
    }

    func testModeAndAppTokens() {
        let name = FilenameFormatter.filename(template: "{app} {mode}", date: date, mode: .window, appName: "Safari", timeZone: utc)
        XCTAssertEqual(name, "Safari Window")
    }

    func testMissingAppCollapsesWhitespace() {
        let name = FilenameFormatter.filename(template: "Shot {app} {date}", date: date, mode: .fullscreen, timeZone: utc)
        XCTAssertEqual(name, "Shot 2026-10-22")
    }

    func testPathSeparatorsAreReplaced() {
        let name = FilenameFormatter.filename(template: "a/b:c", date: date, mode: .area, timeZone: utc)
        XCTAssertEqual(name, "a-b-c")
    }

    func testEmptyResultFallsBack() {
        XCTAssertEqual(FilenameFormatter.filename(template: "{app}", date: date, mode: .area, timeZone: utc), "Screenshot")
        XCTAssertEqual(FilenameFormatter.filename(template: "..", date: date, mode: .area, timeZone: utc), "Screenshot")
    }
}
