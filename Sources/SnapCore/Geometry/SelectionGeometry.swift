import CoreGraphics

/// The rectangle math behind dragging out a selection.
public enum SelectionGeometry {
    /// The selection for a drag from `anchor` to `current`, clipped to `bounds`.
    ///
    /// - `square`: equal sides, following the longer one (Shift).
    /// - `fromCenter`: `anchor` is the center instead of a corner (Option).
    public static func rect(anchor: CGPoint, current: CGPoint, square: Bool, fromCenter: Bool, bounds: CGRect) -> CGRect {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        let rect: CGRect
        if fromCenter {
            rect = CGRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        } else {
            rect = CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy))
        }
        return rect.intersection(bounds)
    }

    /// `rect` moved by `delta`, stopping at the edges of `bounds` rather than shrinking.
    public static func move(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    // MARK: Adjusting a finished selection

    /// The eight grab points of a selection. "Top" is the larger y (AppKit coordinates).
    public enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        /// Where the handle sits on `rect`.
        public func point(on rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
            case .top: CGPoint(x: rect.midX, y: rect.maxY)
            case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
            case .right: CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
            case .bottom: CGPoint(x: rect.midX, y: rect.minY)
            case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
            case .left: CGPoint(x: rect.minX, y: rect.midY)
            }
        }

        var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
        var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }
    }

    /// The handle within `tolerance` of `point`, corners first.
    public static func handle(at point: CGPoint, of rect: CGRect, tolerance: CGFloat = 6) -> Handle? {
        let order: [Handle] = [.topLeft, .topRight, .bottomRight, .bottomLeft, .top, .right, .bottom, .left]
        return order.first { handle in
            let p = handle.point(on: rect)
            return abs(p.x - point.x) <= tolerance && abs(p.y - point.y) <= tolerance
        }
    }

    /// `rect` with the edges belonging to `handle` dragged by `delta`. Edges stop at `bounds` and
    /// can't cross, keeping at least `minimum` points.
    public static func resize(_ rect: CGRect, handle: Handle, by delta: CGVector, within bounds: CGRect, minimum: CGFloat = 4) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(max(minX + delta.dx, bounds.minX), maxX - minimum) }
        if handle.movesMaxX { maxX = max(min(maxX + delta.dx, bounds.maxX), minX + minimum) }
        if handle.movesMinY { minY = min(max(minY + delta.dy, bounds.minY), maxY - minimum) }
        if handle.movesMaxY { maxY = max(min(maxY + delta.dy, bounds.maxY), minY + minimum) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `rect` at `size` (points), keeping its top-left corner and shifting back inside `bounds`
    /// if it would stick out. Never larger than `bounds`.
    public static func resized(_ rect: CGRect, to size: CGSize, within bounds: CGRect) -> CGRect {
        let width = min(max(size.width, 1), bounds.width)
        let height = min(max(size.height, 1), bounds.height)
        let resized = CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
        return move(resized, by: .zero, within: bounds)
    }

    /// Pixel dimensions typed by the user: "800x600", "800 × 600", "800*600" or "800 600".
    public static func parseSize(_ text: String) -> (width: Int, height: Int)? {
        let parts = text.lowercased()
            .split(whereSeparator: { "x×*, ".contains($0) })
            .map(String.init)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else { return nil }
        return (width, height)
    }

    // MARK: Remembering a selection

    /// A selection made on a display, in Quartz global points (top-left origin), back in that
    /// display's view coordinates (bottom-left origin). Nil if it no longer fits the display.
    public static func viewRect(fromGlobal rect: CGRect, displayFrame: CGRect) -> CGRect? {
        let local = CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.height - (rect.maxY - displayFrame.minY),
            width: rect.width,
            height: rect.height
        )
        let clipped = local.intersection(CGRect(origin: .zero, size: displayFrame.size))
        guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { return nil }
        return clipped
    }
}
