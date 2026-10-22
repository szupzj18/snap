import XCTest
@testable import SnapCore

@MainActor
final class CaptureHistoryTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func capture(width: Int = 8, app: String? = nil) -> Capture {
        Capture(
            image: TestImage.solid(width: width, height: 4, red: 1),
            scale: 2,
            mode: .window,
            sourceRect: CGRect(x: 10, y: 20, width: 4, height: 2),
            displayID: 1,
            appName: app
        )
    }

    func testAddStoresNewestFirstAndRestores() async throws {
        let history = CaptureHistory(directory: directory, limit: 10)
        let first = capture(width: 8)
        let second = capture(width: 12, app: "Safari")
        try await history.add(first)
        try await history.add(second)

        XCTAssertEqual(history.entries.map(\.id), [second.id, first.id])
        let restored = try XCTUnwrap(history.capture(for: history.entries[0]))
        XCTAssertEqual(restored.image.width, 12)
        XCTAssertEqual(restored.scale, 2)
        XCTAssertEqual(restored.mode, .window)
        XCTAssertEqual(restored.appName, "Safari")
        XCTAssertEqual(restored.sourceRect, second.sourceRect)
    }

    func testSurvivesReload() async throws {
        let history = CaptureHistory(directory: directory, limit: 10)
        try await history.add(capture())
        let reloaded = CaptureHistory(directory: directory, limit: 10)
        XCTAssertEqual(reloaded.entries, history.entries)
    }

    func testLimitDeletesOldestFiles() async throws {
        let history = CaptureHistory(directory: directory, limit: 2)
        let oldest = capture()
        try await history.add(oldest)
        try await history.add(capture())
        try await history.add(capture())
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertFalse(history.entries.contains { $0.id == oldest.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(oldest.id.uuidString).png").path))

        history.limit = 1
        XCTAssertEqual(history.entries.count, 1)
    }

    func testMissingFilesAreDroppedOnLoad() async throws {
        let history = CaptureHistory(directory: directory, limit: 10)
        try await history.add(capture())
        try FileManager.default.removeItem(at: history.fileURL(for: history.entries[0]))
        XCTAssertEqual(CaptureHistory(directory: directory, limit: 10).entries, [])
    }

    func testRemoveAndClear() async throws {
        let history = CaptureHistory(directory: directory, limit: 10)
        try await history.add(capture())
        try await history.add(capture())
        history.remove(history.entries[0])
        XCTAssertEqual(history.entries.count, 1)
        history.clear()
        XCTAssertEqual(history.entries, [])
        XCTAssertEqual(CaptureHistory(directory: directory, limit: 10).entries, [])
    }

    func testThumbnailIsSmall() async throws {
        let history = CaptureHistory(directory: directory, limit: 10)
        try await history.add(capture(width: 400))
        let thumbnail = try XCTUnwrap(history.thumbnail(for: history.fileURL(for: history.entries[0]), maxPixelSize: 100))
        XCTAssertEqual(thumbnail.width, 100)
    }
}
