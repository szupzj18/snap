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
        XCTAssertFalse(settings.hideDesktopIcons)
        XCTAssertEqual(settings.captureDelay, 5)
        XCTAssertFalse(settings.adjustSelectionBeforeCapture)
        XCTAssertNil(settings.lastAreaSelection)
        XCTAssertEqual(settings.quickAccessAutoClose, 5)
        XCTAssertTrue(settings.historyEnabled)
        XCTAssertEqual(settings.historyLimit, 50)
        XCTAssertEqual(settings.recordingFPS, 30)
        XCTAssertTrue(settings.recordingShowsCursor)
        XCTAssertTrue(settings.playSound)
        XCTAssertTrue(settings.checkForUpdates)
        XCTAssertFalse(settings.recordSystemAudio)
        XCTAssertFalse(settings.recordMicrophone)
    }

    func testValuesPersist() {
        let settings = AppSettings(defaults: defaults)
        settings.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        settings.filenameTemplate = "{mode} {time}"
        settings.afterCapture = [.copyToClipboard]
        settings.windowShadow = false
        settings.hideDesktopIcons = true
        settings.quickAccessAutoClose = 0
        settings.historyEnabled = false
        settings.historyLimit = 200
        settings.recordingFPS = 60
        settings.recordingShowsCursor = false
        settings.playSound = false
        settings.checkForUpdates = false
        settings.recordSystemAudio = true
        settings.recordMicrophone = true

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.saveDirectory.path, "/tmp/shots")
        XCTAssertEqual(reloaded.filenameTemplate, "{mode} {time}")
        XCTAssertEqual(reloaded.afterCapture, [.copyToClipboard])
        XCTAssertFalse(reloaded.windowShadow)
        XCTAssertTrue(reloaded.hideDesktopIcons)
        XCTAssertEqual(reloaded.quickAccessAutoClose, 0)
        XCTAssertFalse(reloaded.historyEnabled)
        XCTAssertEqual(reloaded.historyLimit, 200)
        XCTAssertEqual(reloaded.recordingFPS, 60)
        XCTAssertFalse(reloaded.recordingShowsCursor)
        XCTAssertFalse(reloaded.playSound)
        XCTAssertFalse(reloaded.checkForUpdates)
        XCTAssertTrue(reloaded.recordSystemAudio)
        XCTAssertTrue(reloaded.recordMicrophone)
    }

    func testEmptyActionSetIsKept() {
        let settings = AppSettings(defaults: defaults)
        settings.afterCapture = []
        XCTAssertEqual(AppSettings(defaults: defaults).afterCapture, [])
    }

    func testCaptureDelayIsKeptAndUnknownValuesFallBack() {
        AppSettings(defaults: defaults).captureDelay = 10
        XCTAssertEqual(AppSettings(defaults: defaults).captureDelay, 10)
        defaults.set(7, forKey: "captureDelay")
        XCTAssertEqual(AppSettings(defaults: defaults).captureDelay, 5)
    }

    func testSelectionSettingsAreKept() {
        let settings = AppSettings(defaults: defaults)
        settings.adjustSelectionBeforeCapture = true
        settings.lastAreaSelection = SavedSelection(displayID: 2, rect: CGRect(x: 10, y: 20, width: 300, height: 200))
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.adjustSelectionBeforeCapture)
        XCTAssertEqual(reloaded.lastAreaSelection, SavedSelection(displayID: 2, rect: CGRect(x: 10, y: 20, width: 300, height: 200)))
        reloaded.lastAreaSelection = nil
        XCTAssertNil(AppSettings(defaults: defaults).lastAreaSelection)
    }
}
