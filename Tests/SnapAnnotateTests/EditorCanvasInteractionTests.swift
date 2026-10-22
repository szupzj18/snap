import AppKit
import XCTest
@testable import SnapAnnotate

/// Drives the canvas with synthesized events, in a window that's never shown.
@MainActor
final class EditorCanvasInteractionTests: XCTestCase {
    private var document: AnnotationDocument!
    private var state: EditorState!
    private var canvas: EditorCanvasView!
    private var window: NSWindow!
    private let rect = CGRect(x: 20, y: 30, width: 80, height: 40)

    override func setUp() async throws {
        _ = NSApplication.shared
        // 200×150 px at 1x in a 400×300 canvas: the image sits at (100, 75), one point per pixel.
        document = AnnotationDocument(image: Pixels.solid(width: 200, height: 150), scale: 1)
        document.add(Annotation(shape: .rectangle(rect), color: .red, lineWidth: 4))
        state = EditorState()
        state.tool = .select
        canvas = EditorCanvasView(document: document, state: state)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
    }

    /// Image pixel → window coordinates (bottom-left origin).
    private func windowPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 100 + x, y: 300 - (75 + y))
    }

    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: windowPoint(x, y), modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: code)!
    }

    private func dragRectangle(by dx: CGFloat, _ dy: CGFloat) {
        // Grab the left edge of the rectangle.
        canvas.mouseDown(with: mouse(.leftMouseDown, rect.minX, rect.midY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, rect.minX + dx / 2, rect.midY + dy / 2))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, rect.minX + dx, rect.midY + dy))
        canvas.mouseUp(with: mouse(.leftMouseUp, rect.minX + dx, rect.midY + dy))
    }

    func testDragMovesAnnotationAsOneUndoStep() {
        dragRectangle(by: 30, 20)
        XCTAssertEqual(document.annotations.first?.shape, .rectangle(rect.offsetBy(dx: 30, dy: 20)))
        document.undo()
        XCTAssertEqual(document.annotations.first?.shape, .rectangle(rect))
    }

    func testClickingInsideRectangleSelectsNothing() {
        canvas.mouseDown(with: mouse(.leftMouseDown, rect.midX, rect.midY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, rect.midX + 30, rect.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, rect.midX + 30, rect.midY))
        XCTAssertEqual(document.annotations.first?.shape, .rectangle(rect))
    }

    func testDeleteKeyRemovesSelection() {
        canvas.mouseDown(with: mouse(.leftMouseDown, rect.minX, rect.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, rect.minX, rect.midY))
        canvas.keyDown(with: key(51))
        XCTAssertEqual(document.annotations, [])
    }

    func testToolbarChangesApplyToSelection() {
        canvas.mouseDown(with: mouse(.leftMouseDown, rect.minX, rect.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, rect.minX, rect.midY))
        XCTAssertEqual(state.color, .red, "toolbar follows the selection")
        state.color = .blue
        state.size = .large
        XCTAssertEqual(document.annotations.first?.color, .blue)
        XCTAssertEqual(document.annotations.first?.lineWidth, AnnotationSize.large.lineWidth)
    }

    func testSwitchingToolDeselects() {
        canvas.mouseDown(with: mouse(.leftMouseDown, rect.minX, rect.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, rect.minX, rect.midY))
        state.tool = .arrow
        state.color = .green
        XCTAssertEqual(document.annotations.first?.color, .red)
    }
}
