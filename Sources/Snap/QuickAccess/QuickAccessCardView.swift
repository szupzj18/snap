import AppKit
import SwiftUI

struct QuickAccessCardView: View {
    @ObservedObject var item: QuickAccessItem
    let handlers: QuickAccessHandlers

    var body: some View {
        ZStack {
            DragSource(item: item, handlers: handlers)

            if item.isHovered {
                Color.black.opacity(0.4).allowsHitTesting(false)

                VStack(spacing: 8) {
                    PillButton(title: "Copy", action: handlers.copy)
                    PillButton(title: item.savedURL == nil ? "Save" : "Show in Finder", action: handlers.save)
                }

                VStack {
                    HStack {
                        CornerButton(systemImage: "xmark", help: "Close", action: handlers.close)
                        Spacer()
                        CornerButton(systemImage: "pin.fill", help: "Pin to screen", action: handlers.pin)
                    }
                    Spacer()
                    HStack {
                        CornerButton(systemImage: "pencil", help: "Annotate", action: handlers.edit)
                        Spacer()
                        CornerButton(systemImage: "text.viewfinder", help: "Copy text (OCR)", action: handlers.copyText)
                    }
                }
                .padding(6)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.15))
        )
        .animation(.easeOut(duration: 0.12), value: item.isHovered)
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 110)
                .padding(.vertical, 6)
                .background(.white.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }
}

struct CornerButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.9), in: Circle())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The thumbnail. Also the drag source and the hover tracker, which live in AppKit so they keep
/// working while Snap isn't the active app.
private struct DragSource: NSViewRepresentable {
    let item: QuickAccessItem
    let handlers: QuickAccessHandlers

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView(image: item.capture.image)
        view.onHover = { [weak item] in item?.isHovered = $0 }
        view.fileForDrag = handlers.fileForDrag
        view.onDragEnded = handlers.dragEnded
        view.onClick = handlers.edit
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var fileForDrag: (() -> URL?)?
    var onDragEnded: (() -> Void)?
    var onClick: (() -> Void)?

    private let image: CGImage
    private var mouseDownEvent: NSEvent?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) {
        // Moving onto a button drawn above us isn't leaving the card.
        guard let window, !window.frame.contains(NSEvent.mouseLocation) else { return }
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        guard let url = fileForDrag?() else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: image, size: bounds.size)
        draggingItem.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [draggingItem], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        // Still set means the mouse never moved far enough to start a drag: a plain click.
        if mouseDownEvent != nil {
            onClick?()
        }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            onDragEnded?()
        }
    }
}
