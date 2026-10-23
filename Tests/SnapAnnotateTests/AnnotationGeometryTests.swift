import CoreGraphics
import XCTest
@testable import SnapAnnotate

final class AnnotationGeometryTests: XCTestCase {
    private func make(_ shape: AnnotationShape, lineWidth: CGFloat = 4) -> Annotation {
        Annotation(shape: shape, color: .red, lineWidth: lineWidth)
    }

    func testArrowHitsNearItsLineOnly() {
        let arrow = make(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
        XCTAssertTrue(arrow.contains(CGPoint(x: 50, y: 3), tolerance: 2))
        XCTAssertFalse(arrow.contains(CGPoint(x: 50, y: 20), tolerance: 2))
        XCTAssertFalse(arrow.contains(CGPoint(x: 120, y: 0), tolerance: 2))
    }

    func testRectangleHitsOnStrokeNotInside() {
        let rect = make(.rectangle(CGRect(x: 10, y: 10, width: 100, height: 60)))
        XCTAssertTrue(rect.contains(CGPoint(x: 10, y: 40), tolerance: 2))
        XCTAssertTrue(rect.contains(CGPoint(x: 60, y: 71), tolerance: 2))
        XCTAssertFalse(rect.contains(CGPoint(x: 60, y: 40), tolerance: 2))
    }

    func testFilledShapesHitInside() {
        for shape in [AnnotationShape.highlight(CGRect(x: 0, y: 0, width: 50, height: 50)),
                      .pixelate(CGRect(x: 0, y: 0, width: 50, height: 50)),
                      .blur(CGRect(x: 0, y: 0, width: 50, height: 50))] {
            XCTAssertTrue(make(shape).contains(CGPoint(x: 25, y: 25), tolerance: 0))
            XCTAssertFalse(make(shape).contains(CGPoint(x: 80, y: 25), tolerance: 0))
        }
    }

    func testCounterAndTextHits() {
        let counter = make(.counter(center: CGPoint(x: 50, y: 50), number: 1, radius: 10))
        XCTAssertTrue(counter.contains(CGPoint(x: 57, y: 50), tolerance: 0))
        XCTAssertFalse(counter.contains(CGPoint(x: 70, y: 50), tolerance: 0))

        let text = make(.text(origin: CGPoint(x: 10, y: 10), string: "Hello", fontSize: 30))
        XCTAssertTrue(text.contains(CGPoint(x: 20, y: 25), tolerance: 0))
        XCTAssertFalse(text.contains(CGPoint(x: 5, y: 5), tolerance: 0))
    }

    func testEllipseHitsOnOutlineOnly() {
        let ellipse = make(.ellipse(CGRect(x: 0, y: 0, width: 100, height: 50)))
        XCTAssertTrue(ellipse.contains(CGPoint(x: 50, y: 1), tolerance: 2))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 50, y: 25), tolerance: 2), "center")
        XCTAssertFalse(ellipse.contains(CGPoint(x: 2, y: 2), tolerance: 2), "bounding box corner")
    }

    func testPenAndLineHitNearTheStroke() {
        let pen = make(.freehand([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]))
        XCTAssertTrue(pen.contains(CGPoint(x: 52, y: 25), tolerance: 1))
        XCTAssertFalse(pen.contains(CGPoint(x: 20, y: 30), tolerance: 1))
        let line = make(.line(from: .zero, to: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(line.contains(CGPoint(x: 50, y: 52), tolerance: 1))
        XCTAssertEqual(pen.moved(by: CGVector(dx: 1, dy: 2)).shape,
                       .freehand([CGPoint(x: 1, y: 2), CGPoint(x: 51, y: 2), CGPoint(x: 51, y: 52)]))
    }

    func testMovedShiftsEveryPoint() {
        let delta = CGVector(dx: 5, dy: -3)
        XCTAssertEqual(make(.arrow(from: .zero, to: CGPoint(x: 10, y: 10))).moved(by: delta).shape,
                       .arrow(from: CGPoint(x: 5, y: -3), to: CGPoint(x: 15, y: 7)))
        XCTAssertEqual(make(.blur(CGRect(x: 1, y: 1, width: 2, height: 2))).moved(by: delta).shape,
                       .blur(CGRect(x: 6, y: -2, width: 2, height: 2)))
        let moved = make(.counter(center: .zero, number: 3, radius: 4)).moved(by: delta)
        XCTAssertEqual(moved.shape, .counter(center: CGPoint(x: 5, y: -3), number: 3, radius: 4))
    }

    func testResizedUsesPresetsTimesScale() {
        XCTAssertEqual(make(.rectangle(.zero), lineWidth: 1).resized(to: .large, scale: 2).lineWidth, 18)
        let text = make(.text(origin: .zero, string: "a", fontSize: 1)).resized(to: .small, scale: 2)
        XCTAssertEqual(text.shape, .text(origin: .zero, string: "a", fontSize: 32))
    }

    func testTopmostHitWinsAndReplaceRemoveAreUndoable() {
        let document = AnnotationDocument(image: Pixels.solid(width: 100, height: 100), scale: 1)
        let below = make(.highlight(CGRect(x: 0, y: 0, width: 50, height: 50)))
        let above = make(.counter(center: CGPoint(x: 25, y: 25), number: 1, radius: 10))
        document.add(below)
        document.add(above)
        XCTAssertEqual(document.annotation(at: CGPoint(x: 25, y: 25), tolerance: 0)?.id, above.id)
        XCTAssertEqual(document.annotation(at: CGPoint(x: 45, y: 45), tolerance: 0)?.id, below.id)

        document.replace(above.moved(by: CGVector(dx: 50, dy: 50)))
        XCTAssertEqual(document.annotations.map(\.id), [below.id, above.id], "order is kept")
        document.remove(id: below.id)
        XCTAssertEqual(document.annotations.map(\.id), [above.id])

        document.undo()
        document.undo()
        XCTAssertEqual(document.annotations, [below, above])
    }

    func testReplaceWithIdenticalValueAddsNoUndoStep() {
        let document = AnnotationDocument(image: Pixels.solid(width: 10, height: 10), scale: 1)
        let annotation = make(.rectangle(CGRect(x: 1, y: 1, width: 3, height: 3)))
        document.add(annotation)
        document.replace(annotation)
        document.undo()
        XCTAssertEqual(document.annotations, [])
    }
}
