import AppKit
import SnapCore
import SwiftUI

/// A window for annotating one capture and exporting the result as PNG.
@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    public var onClose: (() -> Void)?

    private let capture: Capture
    private let settings: AppSettings
    let annotationDocument: AnnotationDocument
    let state = EditorState()
    private let renderer: AnnotationRenderer

    public init(capture: Capture, settings: AppSettings) {
        self.capture = capture
        self.settings = settings
        annotationDocument = AnnotationDocument(image: capture.image, scale: capture.scale)
        renderer = AnnotationRenderer(base: capture.image, scale: capture.scale)

        let window = EditorWindow(
            contentRect: CGRect(origin: .zero, size: Self.initialSize(for: capture)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate — \(settings.filename(for: capture))"
        // Wide enough for the whole toolbar.
        window.minSize = CGSize(width: Self.minimumWidth, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.annotationDocument = annotationDocument
        window.onCopy = { [weak self] in self?.copyResult() }
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditorView(
            document: annotationDocument,
            state: state,
            copy: { [weak self] in self?.copyResult() },
            save: { [weak self] in self?.saveResult() }
        ))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func present() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private static let minimumWidth: CGFloat = 860

    private static func initialSize(for capture: Capture) -> CGSize {
        let toolbarHeight: CGFloat = 52
        let margin: CGFloat = 48
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let width = min(max(capture.pointSize.width + margin, minimumWidth), visible.width * 0.85)
        let height = min(max(capture.pointSize.height + margin + toolbarHeight, 420), visible.height * 0.85)
        return CGSize(width: width, height: height)
    }

    // MARK: Export

    private func exportedImage() -> CGImage? {
        renderer.export(annotationDocument.annotations, crop: annotationDocument.crop)
    }

    private func copyResult() {
        guard let image = exportedImage() else { return }
        do {
            try Clipboard.copy(image, scale: capture.scale)
        } catch {
            presentError(error)
        }
    }

    private func saveResult() {
        guard let window, let image = exportedImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = settings.saveDirectory
        panel.nameFieldStringValue = settings.filename(for: capture) + ".png"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try ImageExporter.pngData(image, scale: self.capture.scale).write(to: url)
            } catch {
                self.presentError(error)
            }
        }
    }
}

/// Routes the Edit menu's Undo, Redo and Copy to the document when no text is being edited.
final class EditorWindow: NSWindow {
    weak var annotationDocument: AnnotationDocument?
    var onCopy: (() -> Void)?

    @objc func undo(_ sender: Any?) { annotationDocument?.undo() }
    @objc func redo(_ sender: Any?) { annotationDocument?.redo() }
    @objc func copy(_ sender: Any?) { onCopy?() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): annotationDocument?.canUndo ?? false
        case #selector(redo(_:)): annotationDocument?.canRedo ?? false
        default: super.validateMenuItem(menuItem)
        }
    }
}

struct EditorView: View {
    @ObservedObject var document: AnnotationDocument
    @ObservedObject var state: EditorState
    let copy: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(document: document, state: state, copy: copy, save: save)
            Divider()
            CanvasRepresentable(document: document, state: state)
        }
    }
}

private struct EditorToolbar: View {
    @ObservedObject var document: AnnotationDocument
    @ObservedObject var state: EditorState
    let copy: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button { state.tool = tool } label: {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(state.tool == tool ? Color.accentColor.opacity(0.25) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title) (\(String(tool.key).uppercased()))")
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(RGBA.palette, id: \.self) { color in
                    Button { state.color = color } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay(Circle().strokeBorder(state.color == color ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(state.tool.usesColor ? 1 : 0.35)

            if state.tool == .crop {
                Button("Reset Crop") { document.setCrop(nil) }
                    .fixedSize()
                    .disabled(document.crop == nil)
                    .help("Back to the whole image (Delete)")
            } else {
                Picker("Size", selection: $state.size) {
                    ForEach(AnnotationSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
            }

            Divider().frame(height: 20)

            Button(action: document.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")
            Button(action: document.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
                .help("Redo (⇧⌘Z)")

            Spacer(minLength: 8)

            Button("Copy", action: copy)
                .help("Copy the annotated image (⌘C)")
            Button("Save…", action: save)
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let document: AnnotationDocument
    let state: EditorState

    func makeNSView(context: Context) -> EditorCanvasView {
        EditorCanvasView(document: document, state: state)
    }

    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}
