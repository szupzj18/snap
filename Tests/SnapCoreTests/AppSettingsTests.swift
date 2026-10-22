import XCTest
@testable import SnapCore

final class AppSettingsTests: XCTestCase {
    // A fixed name: macOS keeps an (empty) plist per suite even after it is cleared,
    // so a fresh name per run would leave a new file in ~/Library/Preferences each time.
    private let suiteName = "SnapTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
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
        XCTAssertEqual(settings.quickAccessAutoClose, 5)
        XCTAssertTrue(settings.historyEnabled)
        XCTAssertEqual(settings.historyLimit, 50)
    }

    func testValuesPersist() {
        let settings = AppSettings(defaults: defaults)
        settings.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        settings.filenameTemplate = "{mode} {time}"
        settings.afterCapture = [.copyToClipboard]
        settings.windowShadow = false
        settings.quickAccessAutoClose = 0
        settings.historyEnabled = false
        settings.historyLimit = 200

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.saveDirectory.path, "/tmp/shots")
        XCTAssertEqual(reloaded.filenameTemplate, "{mode} {time}")
        XCTAssertEqual(reloaded.afterCapture, [.copyToClipboard])
        XCTAssertFalse(reloaded.windowShadow)
        XCTAssertEqual(reloaded.quickAccessAutoClose, 0)
        XCTAssertFalse(reloaded.historyEnabled)
        XCTAssertEqual(reloaded.historyLimit, 200)
    }

    func testEmptyActionSetIsKept() {
        let settings = AppSettings(defaults: defaults)
        settings.afterCapture = []
        XCTAssertEqual(AppSettings(defaults: defaults).afterCapture, [])
    }
}
