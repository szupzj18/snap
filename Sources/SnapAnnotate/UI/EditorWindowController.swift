import AppKit
import Combine
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
    private var rememberBackdrop: AnyCancellable?

    public init(capture: Capture, settings: AppSettings) {
        self.capture = capture
        self.settings = settings
        annotationDocument = AnnotationDocument(image: capture.image, scale: capture.scale)
        // Start from the background used last time.
        annotationDocument.backdrop = Backdrop.lastUsed
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
        rememberBackdrop = annotationDocument.$backdrop.sink { Backdrop.lastUsed = $0 }
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
        guard let content = renderer.export(annotationDocument.annotations, crop: annotationDocument.crop) else { return nil }
        let backdrop = annotationDocument.backdrop
        return backdrop.isEnabled ? BackdropRenderer.compose(content, backdrop: backdrop, scale: capture.scale) : content
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
    @State private var showBackdrop = false
    @State private var showPalette = false
    let copy: () -> Void
    let save: () -> Void

    private func toolIcon(_ tool: AnnotationTool, selected: Bool, width: CGFloat = 30) -> some View {
        Image(systemName: tool.systemImage)
            .font(.system(size: 14))
            .frame(width: width, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
            .contentShape(Rectangle())
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button { state.tool = tool } label: { toolIcon(tool, selected: state.tool == tool) }
            .buttonStyle(.plain)
            .help("\(tool.title) (\(String(tool.key).uppercased()))")
    }

    /// One button for a group: click uses the tool it shows, the arrow picks another.
    private func toolMenu(_ group: [AnnotationTool]) -> some View {
        let shown = state.shownTool(for: group)
        return Menu {
            ForEach(group) { tool in
                Button { state.tool = tool } label: {
                    Label("\(tool.title)  (\(String(tool.key).uppercased()))", systemImage: tool.systemImage)
                }
            }
        } label: {
            Image(systemName: shown.systemImage)
        } primaryAction: {
            state.tool = shown
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .frame(height: 28)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(group.contains(state.tool) ? Color.accentColor.opacity(0.25) : .clear))
        .help(group.map(\.title).joined(separator: ", "))
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.toolbar, id: \.self) { group in
                    if group.count == 1 {
                        toolButton(group[0])
                    } else {
                        toolMenu(group)
                    }
                }
            }

            Divider().frame(height: 20)

            // One swatch with the palette behind it keeps the toolbar narrow.
            Button { showPalette.toggle() } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(cgColor: state.color.cgColor))
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                        .frame(width: 18, height: 18)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Color")
            .opacity(state.tool.usesColor ? 1 : 0.35)
            .popover(isPresented: $showPalette, arrowEdge: .bottom) {
                HStack(spacing: 8) {
                    ForEach(RGBA.palette, id: \.self) { color in
                        Button {
                            state.color = color
                            showPalette = false
                        } label: {
                            Circle()
                                .fill(Color(cgColor: color.cgColor))
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                                .frame(width: 20, height: 20)
                                .padding(3)
                                .overlay(Circle().strokeBorder(state.color == color ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }

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

            Menu {
                Button("Fit in Window  ⌘0") { state.zoom = nil }
                ForEach([0.5, 1, 2] as [CGFloat], id: \.self) { level in
                    Button("\(Int(level * 100))%" + (level == 1 ? "  ⌘1" : "")) { state.zoom = level }
                }
            } label: {
                Text("\(Int((state.displayedZoom * 100).rounded()))%")
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom (pinch, ⌘= / ⌘-, ⌘0 to fit)")

            Button(action: document.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")
            Button(action: document.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
                .help("Redo (⇧⌘Z)")

            Spacer(minLength: 8)

            Button { showBackdrop.toggle() } label: {
                Image(systemName: document.backdrop.isEnabled ? "photo.fill.on.rectangle.fill" : "photo.on.rectangle")
            }
            .help("Background: put the screenshot on a backdrop for sharing")
            .popover(isPresented: $showBackdrop, arrowEdge: .bottom) {
                BackdropInspector(document: document)
            }

            Button("Copy", action: copy)
                .fixedSize()
                .help("Copy the annotated image (⌘C)")
            Button("Save…", action: save)
                .fixedSize()
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
