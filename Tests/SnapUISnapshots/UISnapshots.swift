import AppKit
import SwiftUI
import XCTest
import SnapCore
@testable import Snap
@testable import SnapAnnotate
@testable import SnapCapture

/// One PNG per piece of UI that can't be checked by unit tests alone. Run `make ui-snapshots`.
final class UISnapshots: SnapshotTestCase {
    /// Quick Access cards over a wallpaper: idle, hovered, window capture, recording.
    @MainActor
    func testQuickAccess() async throws {
        let landscape = Capture(image: FakeContent.screenshot(width: 2400, height: 1500), scale: 2,
                                mode: .area, sourceRect: .zero, displayID: nil)
        let window = Capture(image: FakeContent.screenshot(width: 1300, height: 1700, transparentMargin: 80), scale: 2,
                             mode: .window, sourceRect: .zero, displayID: nil)
        let recording = Recording(url: URL(fileURLWithPath: "/dev/null"), thumbnail: FakeContent.screenshot(width: 1600, height: 900),
                                  scale: 2, duration: 83, sourceRect: .zero, displayID: nil)
        let videoFrame = Capture(image: recording.thumbnail, scale: 2, mode: .recording, sourceRect: .zero, displayID: nil)
        let handlers = QuickAccessHandlers(copy: {}, save: {}, edit: {}, copyText: {}, pin: {}, exportGIF: {}, close: {},
                                           fileForDrag: { nil }, dragEnded: {})

        func card(_ capture: Capture, hovered: Bool, recording: Recording? = nil) -> some View {
            let item = QuickAccessItem(capture: capture, savedURL: nil, recording: recording)
            item.isHovered = hovered
            let size = QuickAccessCard.cardSize(for: capture.pointSize)
            return QuickAccessCardView(item: item, handlers: handlers).frame(width: size.width, height: size.height)
        }
        let scene = ZStack {
            Wallpaper()
            HStack(alignment: .bottom, spacing: 28) {
                card(landscape, hovered: false)
                card(landscape, hovered: true)
                card(window, hovered: true)
                card(videoFrame, hovered: false, recording: recording)
                card(videoFrame, hovered: true, recording: recording)
            }
            .padding(30)
        }
        try await Snapshot.capture(Snapshot.window(scene), name: "quick-access", includeTitleBar: false)
    }

    /// Area selection mid-drag after a Space-move, with the magnifier over text.
    @MainActor
    func testAreaSelection() async throws {
        let size = CGSize(width: 600, height: 400)
        let display = DisplaySnapshot(displayID: 0, frame: CGRect(origin: .zero, size: size), scale: 2,
                                      image: FakeContent.code(width: 1200, height: 800))
        let view = AreaSelectionView(frame: CGRect(origin: .zero, size: size), snapshot: display)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view

        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, 100, 100))
        // End over the word "Image" so the magnifier shows real detail.
        view.mouseDragged(with: mouse(.leftMouseDragged, 215, 293))
        try await Snapshot.capture(window, name: "area-selection", includeTitleBar: false)
    }

    /// The editor with a few annotations.
    @MainActor
    func testEditor() async throws {
        let controller = editor()
        let document = controller.annotationDocument
        document.add(Annotation(shape: .arrow(from: CGPoint(x: 160, y: 1100), to: CGPoint(x: 900, y: 520)), color: .red, lineWidth: 10))
        document.add(Annotation(shape: .rectangle(CGRect(x: 1000, y: 300, width: 600, height: 340)), color: .green, lineWidth: 10))
        document.add(Annotation(shape: .text(origin: CGPoint(x: 1050, y: 700), string: "Fixed in 0.2", fontSize: 48), color: .red, lineWidth: 0))
        document.add(Annotation(shape: .pixelate(CGRect(x: 160, y: 300, width: 420, height: 160)), color: .red, lineWidth: 0))
        document.add(Annotation(shape: .counter(center: CGPoint(x: 1700, y: 1000), number: 1, radius: 30), color: .blue, lineWidth: 0))
        document.add(Annotation(shape: .spotlight(CGRect(x: 980, y: 280, width: 640, height: 380)), color: .red, lineWidth: 0))
        document.add(Annotation(shape: .ellipse(CGRect(x: 1560, y: 900, width: 280, height: 200)), color: .orange, lineWidth: 10))
        document.add(Annotation(shape: .freehand((0..<40).map { CGPoint(x: 300 + CGFloat($0) * 12, y: 1180 + sin(CGFloat($0) / 3) * 30) }),
                                color: .purple, lineWidth: 10))
        try await Snapshot.capture(controller.window!, name: "editor")
    }

    /// The editor's crop tool: the whole image with everything outside the crop dimmed.
    @MainActor
    func testEditorCrop() async throws {
        let controller = editor(image: FakeContent.halves(width: 1200, height: 700))
        controller.annotationDocument.add(Annotation(shape: .arrow(from: CGPoint(x: 100, y: 600), to: CGPoint(x: 500, y: 300)),
                                                     color: .yellow, lineWidth: 10))
        controller.annotationDocument.setCrop(CGRect(x: 200, y: 150, width: 700, height: 450))
        controller.state.tool = .crop
        try await Snapshot.capture(controller.window!, name: "editor-crop")
    }

    /// The editor with a background on, at the narrowest window size, plus the Background popover.
    @MainActor
    func testEditorBackdrop() async throws {
        let controller = editor()
        controller.annotationDocument.add(Annotation(shape: .arrow(from: CGPoint(x: 160, y: 1100), to: CGPoint(x: 900, y: 520)),
                                                     color: .red, lineWidth: 10))
        controller.annotationDocument.backdrop = Backdrop(isEnabled: true, fill: Backdrop.gradients[0], padding: 64,
                                                          cornerRadius: 12, shadow: 0.6, aspect: .automatic)
        controller.window?.setContentSize(CGSize(width: 860, height: 600))
        try await Snapshot.capture(controller.window!, name: "editor-backdrop")

        let inspector = Snapshot.window(BackdropInspector(document: controller.annotationDocument))
        try await Snapshot.capture(inspector, name: "backdrop-inspector", includeTitleBar: false)
    }

    /// The trim window with AVKit's trim bar open over a made-up recording.
    @MainActor
    func testTrim() async throws {
        let url = try await FakeContent.movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let trimmer = TrimWindowController(url: url) { _ in }
        trimmer.window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        trimmer.window.orderFrontRegardless()
        let trimming = Task { await trimmer.beginTrimming() }
        try await Snapshot.capture(trimmer.window, name: "trim")
        trimming.cancel()
    }

    /// The history window with a handful of captures of different shapes.
    @MainActor
    func testHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CaptureHistory(directory: directory, limit: 50)
        for (width, height) in [(2400, 1500), (1300, 1700), (1800, 600), (1200, 1200), (2000, 1100)] {
            try await history.add(Capture(image: FakeContent.screenshot(width: width, height: height), scale: 2,
                                          mode: .area, sourceRect: .zero, displayID: nil))
        }
        let ignore: (HistoryEntry) -> Void = { _ in }
        let window = HostingWindow.make(
            title: "Capture History",
            rootView: HistoryView(history: history, handlers: HistoryHandlers(copy: ignore, edit: ignore, pin: ignore, reveal: ignore)),
            resizable: true
        )
        window.setContentSize(CGSize(width: 760, height: 520))
        try await Snapshot.capture(window, name: "history")
    }

    /// Settings, General tab, with default values.
    @MainActor
    func testSettings() async throws {
        let suite = "SnapUISnapshots.settings"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let window = HostingWindow.make(title: "Snap Settings", rootView: SettingsView(settings: settings))
        try await Snapshot.capture(window, name: "settings")
    }

    @MainActor
    private func editor(image: CGImage = FakeContent.screenshot(width: 2000, height: 1300)) -> EditorWindowController {
        let suite = "SnapUISnapshots.editor"
        // Each snapshot starts without the background another one turned on.
        Backdrop.lastUsed = Backdrop()
        let capture = Capture(image: image, scale: 2, mode: .area, sourceRect: .zero, displayID: nil)
        let controller = EditorWindowController(capture: capture, settings: AppSettings(defaults: UserDefaults(suiteName: suite)!))
        controller.window?.setContentSize(CGSize(width: 960, height: 600))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return controller
    }
}
