import AppKit

public enum Clipboard {
    /// Puts the image on the general pasteboard as PNG (keeps transparency and DPI) and TIFF
    /// (for apps that only read TIFF).
    public static func copy(_ image: CGImage, scale: CGFloat) throws {
        let item = NSPasteboardItem()
        item.setData(try ImageExporter.pngData(image, scale: scale), forType: .png)
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
