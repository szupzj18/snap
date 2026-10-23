import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns an existing image (a file, or whatever is on the clipboard) into a `Capture`, so it can be
/// annotated or pinned like a screenshot.
public enum ImageImport {
    public enum Failure: LocalizedError {
        case unreadable(URL)

        public var errorDescription: String? {
            switch self {
            case let .unreadable(url): "Snap can't open “\(url.lastPathComponent)” as an image."
            }
        }
    }

    public static func capture(fromFile url: URL) throws -> Capture {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let capture = capture(from: source) else { throw Failure.unreadable(url) }
        return capture
    }

    /// Image data on the pasteboard, or a copied image file. Nil if there's neither.
    public static func capture(from pasteboard: NSPasteboard) -> Capture? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let capture = capture(from: source) {
                return capture
            }
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first {
            return try? capture(fromFile: url)
        }
        return nil
    }

    public static func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil
            || pasteboard.canReadObject(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ])
    }

    private static func capture(from source: CGImageSource) -> Capture? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return Capture(image: image, scale: scale(fromDPI: properties?[kCGImagePropertyDPIWidth] as? Double),
                       mode: .area, sourceRect: .zero, displayID: nil)
    }

    /// 144 DPI (how Snap and macOS save Retina screenshots) means 2x; anything unknown is 1x.
    static func scale(fromDPI dpi: Double?) -> CGFloat {
        guard let dpi, dpi > 72 else { return 1 }
        return min(max((dpi / 72).rounded(), 1), 3)
    }
}
