import AVFoundation
import AppKit
import ScreenCaptureKit
import SwiftUI
import XCTest

/// Base class: snapshot tests only run with `SNAP_UI_SNAPSHOTS=1` (see `make ui-snapshots`).
/// They need Screen Recording access for the process running them, and briefly put windows
/// far outside every display, so nothing shows on screen.
class SnapshotTestCase: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_UI_SNAPSHOTS"] == "1",
                          "Set SNAP_UI_SNAPSHOTS=1 (or run `make ui-snapshots`)")
    }
}

@MainActor
enum Snapshot {
    /// `SNAP_UI_SNAPSHOTS_DIR`, or `build/ui-snapshots` in the repository.
    static var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SNAP_UI_SNAPSHOTS_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SnapUISnapshots
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("build/ui-snapshots", isDirectory: true)
    }

    /// A window for a SwiftUI scene. It needs a title bar: ScreenCaptureKit refuses borderless
    /// windows that are off screen.
    static func window<Content: View>(_ rootView: Content, size: CGSize? = nil) -> NSWindow {
        let host = NSHostingView(rootView: rootView)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size ?? host.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        return window
    }

    /// Shows `window` off screen, captures it and writes `<name>.png`. Scenes built only for the
    /// snapshot can drop the title bar; real windows keep it.
    @discardableResult
    static func capture(_ window: NSWindow, name: String, includeTitleBar: Bool = true) async throws -> URL {
        _ = NSApplication.shared
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Let SwiftUI lay out and the window server pick up the window.
        try await Task.sleep(nanoseconds: 800_000_000)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let scWindow = try XCTUnwrap(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) },
                                     "window not found by ScreenCaptureKit")
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.ignoreShadowsSingleWindow = true
        // Otherwise the real pointer is drawn in wherever it happens to be.
        configuration.showsCursor = false
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        if !includeTitleBar {
            let titleBar = (window.frame.height - window.contentLayoutRect.height) * scale
            let content = CGRect(x: 0, y: titleBar, width: CGFloat(image.width), height: CGFloat(image.height) - titleBar).integral
            image = try XCTUnwrap(image.cropping(to: content))
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
        print("snapshot: \(url.path)")
        return url
    }
}

/// Made-up screen content, so snapshots never contain anything real.
enum FakeContent {
    /// A light window: title bar strip and colored lines standing in for text. With
    /// `transparentMargin`, it's a window capture with rounded corners and a shadow.
    static func screenshot(width: Int, height: Int, transparentMargin: Int = 0) -> CGImage {
        let context = makeContext(width: width, height: height)
        let margin = CGFloat(transparentMargin)
        let body = CGRect(x: margin, y: margin, width: CGFloat(width) - 2 * margin, height: CGFloat(height) - 2 * margin)
        if margin > 0 {
            context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
        }
        let radius: CGFloat = margin > 0 ? 20 : 0
        context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.91, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: body.minX, y: body.maxY - 70, width: body.width, height: 70))
        let colors = [
            CGColor(srgbRed: 0.25, green: 0.5, blue: 0.95, alpha: 1),
            CGColor(srgbRed: 0.95, green: 0.6, blue: 0.2, alpha: 1),
            CGColor(srgbRed: 0.3, green: 0.75, blue: 0.45, alpha: 1),
        ]
        for row in 0..<8 {
            context.setFillColor(colors[row % 3])
            context.fill(CGRect(x: body.minX + 60, y: body.maxY - 130 - CGFloat(row) * 60,
                                width: CGFloat(200 + (row * 97) % 500), height: 22))
        }
        return context.makeImage()!
    }

    /// Lines of colored code, for things that need fine detail (the magnifier).
    static func code(width: Int, height: Int, lines: Int = 10) -> CGImage {
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let step = CGFloat(height) / CGFloat(lines + 1)
        for line in 0..<lines {
            ("func capture() -> Image  // line \(line)" as NSString).draw(
                at: CGPoint(x: 40, y: CGFloat(height) - step * CGFloat(line + 1) - 15),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: step * 0.45, weight: .regular),
                    .foregroundColor: NSColor(hue: CGFloat(line) / CGFloat(lines), saturation: 0.8, brightness: 0.6, alpha: 1),
                ]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    /// Red top half, blue bottom half: makes orientation and cropping easy to judge.
    static func halves(width: Int, height: Int) -> CGImage {
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.15, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }

    private static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}

extension FakeContent {
    /// A short H.264 movie of a made-up window with a bar sliding across it.
    static func movie(seconds: Double = 2, fps: Int32 = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let size = (width: 960, height: 600)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let background = screenshot(width: size.width, height: size.height)
        let frames = Int(seconds * Double(fps))
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer!), width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            context.draw(background, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: CGFloat(index) / CGFloat(frames) * CGFloat(size.width - 120), y: 80, width: 120, height: 40))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}

/// A stand-in desktop, so translucent UI has something colorful behind it.
struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.3, blue: 0.75), Color(red: 0.85, green: 0.45, blue: 0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
