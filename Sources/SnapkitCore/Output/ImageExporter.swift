import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExportError: Error {
    case encodingFailed
}

/// Encodes captures as PNG and writes them to disk.
public enum ImageExporter {
    /// PNG data with DPI metadata matching `scale`, so a 2x capture opens at its on-screen size.
    public static func pngData(_ image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed
        }
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.encodingFailed }
        return data as Data
    }

    /// Writes a PNG into `directory`, adding " (2)", " (3)", ... if the name is taken.
    @discardableResult
    public static func writePNG(_ image: CGImage, scale: CGFloat, to directory: URL, filename: String) throws -> URL {
        let data = try pngData(image, scale: scale)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(in: directory, filename: filename, pathExtension: "png")
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    public static func uniqueURL(in directory: URL, filename: String, pathExtension: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(filename).appendingPathExtension(pathExtension)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(filename) (\(counter))").appendingPathExtension(pathExtension)
            counter += 1
        }
        return candidate
    }
}
