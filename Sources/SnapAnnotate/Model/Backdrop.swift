import CoreGraphics

/// A background behind the screenshot for sharing: fill, padding, rounded corners, shadow, an
/// optional window or browser frame and the canvas's aspect ratio. Lengths are in points; the
/// renderer multiplies by the capture scale.
public struct Backdrop: Equatable {
    public enum Fill: Equatable {
        case gradient(top: RGBA, bottom: RGBA)
        case solid(RGBA)
        /// An image (the desktop picture), scaled to cover the canvas.
        case image(CGImage)
        /// No background: just padding, rounded corners and shadow on transparency.
        case clear

        public static func == (lhs: Fill, rhs: Fill) -> Bool {
            switch (lhs, rhs) {
            case let (.gradient(a, b), .gradient(c, d)): a == c && b == d
            case let (.solid(a), .solid(b)): a == b
            case let (.image(a), .image(b)): a === b
            case (.clear, .clear): true
            default: false
            }
        }
    }

    public enum Aspect: String, CaseIterable, Identifiable {
        case automatic, square, standard, wide

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .automatic: "Auto"
            case .square: "1:1"
            case .standard: "4:3"
            case .wide: "16:9"
            }
        }

        /// Width over height, or nil to follow the screenshot.
        var ratio: CGFloat? {
            switch self {
            case .automatic: nil
            case .square: 1
            case .standard: 4.0 / 3.0
            case .wide: 16.0 / 9.0
            }
        }
    }

    /// A title bar drawn above the screenshot, as if it were a Mac window.
    public enum Frame: String, CaseIterable, Identifiable {
        case none
        /// Traffic lights.
        case window
        /// Traffic lights and an address bar.
        case browser

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .none: "None"
            case .window: "Window"
            case .browser: "Browser"
            }
        }

        /// The bar's height in points.
        var barHeight: CGFloat {
            switch self {
            case .none: 0
            case .window: 28
            case .browser: 40
            }
        }
    }

    public var isEnabled: Bool
    public var fill: Fill
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    /// 0 (none) to 1 (strong).
    public var shadow: CGFloat
    public var aspect: Aspect
    public var frame: Frame
    public var darkFrame: Bool

    public init(isEnabled: Bool = false, fill: Fill = Backdrop.gradients[0], padding: CGFloat = 64,
                cornerRadius: CGFloat = 12, shadow: CGFloat = 0.5, aspect: Aspect = .automatic,
                frame: Frame = .none, darkFrame: Bool = false) {
        self.isEnabled = isEnabled
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.aspect = aspect
        self.frame = frame
        self.darkFrame = darkFrame
    }

    /// The last settings used, so a new editor starts where the previous one left off.
    static var lastUsed = Backdrop()

    public static let gradients: [Fill] = [
        .gradient(top: RGBA(0.50, 0.50, 0.84), bottom: RGBA(0.57, 0.92, 0.89)),   // violet → aqua
        .gradient(top: RGBA(1.00, 0.54, 0.40), bottom: RGBA(0.94, 0.38, 0.57)),   // sunset
        .gradient(top: RGBA(0.31, 0.67, 1.00), bottom: RGBA(0.00, 0.95, 1.00)),   // ocean
        .gradient(top: RGBA(0.26, 0.91, 0.48), bottom: RGBA(0.22, 0.98, 0.84)),   // mint
        .gradient(top: RGBA(0.88, 0.76, 0.99), bottom: RGBA(0.56, 0.77, 0.99)),   // lavender
        .gradient(top: RGBA(1.00, 0.87, 0.88), bottom: RGBA(0.93, 0.61, 0.65)),   // peach
        .gradient(top: RGBA(1.00, 0.77, 0.19), bottom: RGBA(1.00, 0.54, 0.00)),   // Snap yellow
        .gradient(top: RGBA(0.17, 0.18, 0.22), bottom: RGBA(0.08, 0.09, 0.11)),   // graphite
    ]

    public static let solids: [Fill] = [
        .solid(RGBA(1, 1, 1)),
        .solid(RGBA(0.95, 0.95, 0.96)),
        .solid(RGBA(0.11, 0.11, 0.13)),
    ]
}
