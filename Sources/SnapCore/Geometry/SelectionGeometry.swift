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
}
