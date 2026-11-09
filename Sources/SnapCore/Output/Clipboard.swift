import AppKit

public enum Clipboard {
    /// Puts the image on the general pasteboard as PNG (keeps transparency and DPI) and TIFF
    /// (for apps that only read TIFF). Returns the PNG data it put there.
    @discardableResult
    public static func copy(_ image: CGImage, scale: CGFloat) throws -> Data {
        let png = try ImageExporter.pngData(image, scale: scale)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return png
    }

    /// Whether the general pasteboard still holds exactly this PNG and it reads back as an image.
    public static func holdsImage(png: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.data(forType: .png) == png && NSImage(pasteboard: pasteboard) != nil
    }

    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
