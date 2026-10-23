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

    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat,
                       flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: windowPoint(x, y), modifierFlags: flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
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

    func testCropToolSetsCropAndShowsOnlyThatPart() {
        state.tool = .crop
        canvas.mouseDown(with: mouse(.leftMouseDown, 10, 10))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 110, 90))
        canvas.mouseUp(with: mouse(.leftMouseUp, 110, 90))
        XCTAssertEqual(document.crop, CGRect(x: 10, y: 10, width: 100, height: 80))
        canvas.keyDown(with: key(36)) // Return: done cropping
        XCTAssertEqual(state.tool, .select)
    }

    func testShiftDrawsSquaresAndStraightArrows() {
        state.tool = .rectangle
        canvas.mouseDown(with: mouse(.leftMouseDown, 120, 20))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 150, 80, flags: .shift))
        canvas.mouseUp(with: mouse(.leftMouseUp, 150, 80, flags: .shift))
        XCTAssertEqual(document.annotations.last?.shape, .rectangle(CGRect(x: 120, y: 20, width: 60, height: 60)))

        state.tool = .arrow
        canvas.mouseDown(with: mouse(.leftMouseDown, 10, 100))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 90, 104, flags: .shift))
        canvas.mouseUp(with: mouse(.leftMouseUp, 90, 104, flags: .shift))
        guard case let .arrow(from, to)? = document.annotations.last?.shape else { return XCTFail("no arrow") }
        XCTAssertEqual(from, CGPoint(x: 10, y: 100))
        XCTAssertEqual(to.y, 100, accuracy: 0.001, "snapped to horizontal")
    }

    func testDoubleClickEditsExistingText() throws {
        let text = Annotation(shape: .text(origin: CGPoint(x: 20, y: 100), string: "Hello", fontSize: 20), color: .blue, lineWidth: 0)
        document.add(text)
        canvas.mouseDown(with: mouse(.leftMouseDown, 30, 110, clicks: 1))
        canvas.mouseUp(with: mouse(.leftMouseUp, 30, 110, clicks: 1))
        canvas.mouseDown(with: mouse(.leftMouseDown, 30, 110, clicks: 2))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(field.stringValue, "Hello")
        field.stringValue = "Hello again"
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(document.annotations.last?.id, text.id, "replaced, not added")
        XCTAssertEqual(document.annotations.last?.shape, .text(origin: CGPoint(x: 20, y: 100), string: "Hello again", fontSize: 20))
        XCTAssertEqual(document.annotations.count, 2)
    }

    func testDrawingStillLandsRightWithABackground() {
        // 200×150 px at 1x with 40 pt padding: a 280×230 canvas, centered in 400×300, so the
        // screenshot sits at (100, 75) again and points map one to one.
        document.backdrop = Backdrop(isEnabled: true, fill: .solid(.white), padding: 40, cornerRadius: 0, shadow: 0)
        state.tool = .rectangle
        canvas.mouseDown(with: mouse(.leftMouseDown, 120, 20))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 170, 60))
        canvas.mouseUp(with: mouse(.leftMouseUp, 170, 60))
        XCTAssertEqual(document.annotations.last?.shape, .rectangle(CGRect(x: 120, y: 20, width: 50, height: 40)))
    }

    func testPenDrawsAFreehandStroke() {
        state.tool = .pen
        canvas.mouseDown(with: mouse(.leftMouseDown, 10, 100))
        for x in stride(from: 20, through: 80, by: 10) {
            canvas.mouseDragged(with: mouse(.leftMouseDragged, CGFloat(x), 100 + CGFloat(x % 20)))
        }
        canvas.mouseUp(with: mouse(.leftMouseUp, 80, 100))
        guard case let .freehand(points)? = document.annotations.last?.shape else { return XCTFail("no stroke") }
        XCTAssertEqual(points.first, CGPoint(x: 10, y: 100))
        XCTAssertEqual(points.count, 8)
    }

    func testGroupedToolRemembersLastUsed() {
        XCTAssertEqual(state.shownTool(for: AnnotationTool.groups[0]), .rectangle)
        state.tool = .ellipse
        state.tool = .arrow
        XCTAssertEqual(state.shownTool(for: AnnotationTool.groups[0]), .ellipse)
    }
}
