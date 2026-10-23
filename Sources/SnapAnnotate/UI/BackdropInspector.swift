import AppKit
import ImageIO
import SwiftUI

/// The Background popover: fill, padding, corners, shadow and canvas shape.
struct BackdropInspector: View {
    @ObservedObject var document: AnnotationDocument
    /// The current desktop picture, if it can be read (some dynamic wallpapers can't).
    @State private var wallpaper: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Background", isOn: $document.backdrop.isEnabled)
                .toggleStyle(.switch)
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                ForEach(Array((Backdrop.gradients + Backdrop.solids).enumerated()), id: \.offset) { _, fill in
                    swatch(fill) { FillPreview(fill: fill) }
                }
                if let wallpaper {
                    swatch(.image(wallpaper)) { FillPreview(fill: .image(wallpaper)) }
                        .help("Desktop picture")
                }
                swatch(.clear) {
                    Image(systemName: "square.dashed").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .help("No background")
            }

            Group {
                slider("Padding", value: $document.backdrop.padding, in: 0...160)
                slider("Corners", value: $document.backdrop.cornerRadius, in: 0...32)
                slider("Shadow", value: $document.backdrop.shadow, in: 0...1)
                Picker("Shape", selection: $document.backdrop.aspect) {
                    ForEach(Backdrop.Aspect.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!document.backdrop.isEnabled)
        }
        .padding(16)
        .frame(width: 300)
        .task { wallpaper = Self.desktopPicture() }
    }

    /// Picking a fill also turns the background on.
    private func swatch<Label: View>(_ fill: Backdrop.Fill, @ViewBuilder label: () -> Label) -> some View {
        let selected = document.backdrop.isEnabled && document.backdrop.fill == fill
        return Button {
            document.backdrop.fill = fill
            document.backdrop.isEnabled = true
        } label: {
            label()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.15)))
                .padding(1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func slider(_ title: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title).frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private static func desktopPicture() -> CGImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Big enough for any canvas, small enough to keep the editor quick.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
        ] as CFDictionary)
    }
}

/// A small sample of a fill, drawn with the same code as the canvas.
private struct FillPreview: View {
    let fill: Backdrop.Fill

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                // SwiftUI's canvas is y-down already, like the renderer expects.
                BackdropRenderer.drawFill(fill, in: CGRect(origin: .zero, size: size), context: cg)
            }
        }
    }
}
