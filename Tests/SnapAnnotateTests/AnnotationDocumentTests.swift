import CoreGraphics
import XCTest
@testable import SnapAnnotate

final class AnnotationDocumentTests: XCTestCase {
    private func makeDocument() -> AnnotationDocument {
        AnnotationDocument(image: Pixels.solid(width: 10, height: 10), scale: 1)
    }

    private func rectangle() -> Annotation {
        Annotation(shape: .rectangle(CGRect(x: 1, y: 1, width: 3, height: 3)), color: .red, lineWidth: 1)
    }

    func testUndoRedo() {
        let document = makeDocument()
        let first = rectangle()
        let second = rectangle()
        document.add(first)
        document.add(second)
        XCTAssertEqual(document.annotations, [first, second])

        document.undo()
        XCTAssertEqual(document.annotations, [first])
        XCTAssertTrue(document.canRedo)

        document.undo()
        XCTAssertEqual(document.annotations, [])
        XCTAssertFalse(document.canUndo)

        document.redo()
        document.redo()
        XCTAssertEqual(document.annotations, [first, second])
        XCTAssertFalse(document.canRedo)
    }

    func testNewEditClearsRedo() {
        let document = makeDocument()
        document.add(rectangle())
        document.undo()
        document.add(rectangle())
        XCTAssertFalse(document.canRedo)
        XCTAssertEqual(document.annotations.count, 1)
    }

    func testCounterNumbersContinueAndFollowUndo() {
        let document = makeDocument()
        XCTAssertEqual(document.nextCounterNumber, 1)
        document.add(Annotation(shape: .counter(center: .zero, number: 1, radius: 5), color: .red, lineWidth: 1))
        document.add(Annotation(shape: .counter(center: .zero, number: 2, radius: 5), color: .red, lineWidth: 1))
        XCTAssertEqual(document.nextCounterNumber, 3)
        document.undo()
        XCTAssertEqual(document.nextCounterNumber, 2)
    }
}

final class AnnotationDocumentCropTests: XCTestCase {
    func testCropIsUndoableAndClamped() {
        let document = AnnotationDocument(image: Pixels.solid(width: 100, height: 80), scale: 1)
        document.setCrop(CGRect(x: 10.4, y: -5, width: 50, height: 40.2))
        XCTAssertEqual(document.crop, CGRect(x: 10, y: 0, width: 51, height: 36))
        XCTAssertEqual(document.visibleRect, document.crop)
        XCTAssertTrue(document.isEdited)

        document.undo()
        XCTAssertNil(document.crop)
        XCTAssertEqual(document.visibleRect, CGRect(x: 0, y: 0, width: 100, height: 80))
        document.redo()
        XCTAssertNotNil(document.crop)
    }

    func testCroppingToWholeImageMeansNoCrop() {
        let document = AnnotationDocument(image: Pixels.solid(width: 100, height: 80), scale: 1)
        document.setCrop(CGRect(x: -10, y: -10, width: 200, height: 200))
        XCTAssertNil(document.crop)
        XCTAssertFalse(document.canUndo, "no change, no undo step")
    }

    func testAnnotationUndoKeepsCrop() {
        let document = AnnotationDocument(image: Pixels.solid(width: 100, height: 80), scale: 1)
        document.setCrop(CGRect(x: 0, y: 0, width: 50, height: 50))
        document.add(Annotation(shape: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)), color: .red, lineWidth: 1))
        document.undo()
        XCTAssertEqual(document.annotations, [])
        XCTAssertEqual(document.crop, CGRect(x: 0, y: 0, width: 50, height: 50))
    }
}
