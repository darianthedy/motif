import SwiftUI

/// An arrow's geometry from one point to another, for the overlay and the drag preview: the
/// shaft's centre line up to the head's base, the head, and the whole outline.
struct BoardArrowShape {
    var shaft: Path
    var head: Path
    var outline: Path
    /// Where the shaft meets the head.
    var base: CGPoint
    var width: CGFloat

    /// Nil when the two points are the same. `size` is one square's side.
    init?(from start: CGPoint, to end: CGPoint, size: CGFloat) {
        let dx = end.x - start.x, dy = end.y - start.y, length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return nil }
        let ux = dx / length, uy = dy / length
        let head = min(size * 0.42, length)
        width = size * 0.15
        // The shaft stops at the head's base, so a dashed shaft doesn't show through the head.
        base = CGPoint(x: end.x - ux * head, y: end.y - uy * head)
        func side(_ point: CGPoint, _ offset: CGFloat) -> CGPoint { CGPoint(x: point.x - uy * offset, y: point.y + ux * offset) }
        shaft = Path(); shaft.move(to: start); shaft.addLine(to: base)
        self.head = Path()
        self.head.move(to: end); self.head.addLine(to: side(base, head / 2)); self.head.addLine(to: side(base, -head / 2))
        self.head.closeSubpath()
        outline = Path()
        outline.move(to: side(start, width / 2))
        for point in [side(base, width / 2), side(base, head / 2), end, side(base, -head / 2),
                      side(base, -width / 2), side(start, -width / 2)] {
            outline.addLine(to: point)
        }
        outline.closeSubpath()
    }

    /// Filled: own side a solid shaft, their side a dashed one.
    func fill(side: BoardArrow.Side, color: Color, context: GraphicsContext) {
        let style = side == .own ? StrokeStyle(lineWidth: width, lineCap: .round)
            : StrokeStyle(lineWidth: width, lineCap: .butt, dash: [width * 1.2, width * 0.9])
        context.stroke(shaft, with: .color(color), style: style)
        context.fill(head, with: .color(color))
    }
}
