import XCTest
@testable import SnapkitCore

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "SnapkitTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.saveDirectory, AppSettings.defaultSaveDirectory)
        XCTAssertEqual(settings.filenameTemplate, FilenameFormatter.defaultTemplate)
        XCTAssertEqual(settings.afterCapture, AppSettings.defaultAfterCapture)
        XCTAssertTrue(settings.windowShadow)
    }

    func testValuesPersist() {
        let settings = AppSettings(defaults: defaults)
        settings.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        settings.filenameTemplate = "{mode} {time}"
        settings.afterCapture = [.copyToClipboard]
        settings.windowShadow = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.saveDirectory.path, "/tmp/shots")
        XCTAssertEqual(reloaded.filenameTemplate, "{mode} {time}")
        XCTAssertEqual(reloaded.afterCapture, [.copyToClipboard])
        XCTAssertFalse(reloaded.windowShadow)
    }

    func testEmptyActionSetIsKept() {
        let settings = AppSettings(defaults: defaults)
        settings.afterCapture = []
        XCTAssertEqual(AppSettings(defaults: defaults).afterCapture, [])
    }
}
