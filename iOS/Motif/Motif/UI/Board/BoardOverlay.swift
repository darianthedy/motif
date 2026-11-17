import SwiftUI

/// Mark shapes, dots, rings and arrows in one `Canvas` pass above the squares (Scan plan §4). It
/// takes no touches: the squares under it stay the buttons. Every mark has a shape as well as
/// a colour, so none relies on colour alone. Tint fills sit
/// under the pieces, in `BoardView`'s squares (`SquareMark.fill`).
struct BoardOverlay: View {
    let annotations: BoardAnnotations
    let orientation: Side
    /// One square's side.
    let size: CGFloat
    var body: some View {
        Canvas { context, _ in
            for (square, mark) in annotations.tints {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                drawTint(mark, in: rect, context: context)
            }
            for square in annotations.dots {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                let dot = rect.insetBy(dx: size * 0.37, dy: size * 0.37)
                context.fill(Path(ellipseIn: dot), with: .color(BoardPalette.markDot))
                context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: max(1, size * 0.03))
            }
            for (square, ring) in annotations.rings {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                drawRing(ring, in: rect, context: context)
            }
            for arrow in annotations.arrows { drawArrow(arrow, context: context) }
        } symbols: {
            Badge(systemImage: "exclamationmark", fill: BoardPalette.markRed, foreground: .white, size: badgeSize).tag(Symbol.red)
            Badge(systemImage: "equal", fill: BoardPalette.markOrange, foreground: .black, size: badgeSize).tag(Symbol.orange)
            Badge(systemImage: "checkmark", fill: BoardPalette.ringCorrect, foreground: .white, size: badgeSize).tag(Symbol.correct)
            Badge(systemImage: "xmark", fill: BoardPalette.ringExtra, foreground: .white, size: badgeSize).tag(Symbol.extra)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private enum Symbol: Hashable { case red, orange, correct, extra }
    private var badgeSize: CGFloat { (size * 0.36).rounded() }

    /// A square's frame on a board of 8 × `size`, as seen from `orientation`; nil off the board.
    static func rect(_ square: String, _ orientation: Side, _ size: CGFloat) -> CGRect? {
        guard square.count == 2, let file = square.first?.asciiValue, let rank = square.last?.wholeNumberValue,
              (97...104).contains(file), (1...8).contains(rank) else { return nil }
        let column = orientation == .white ? Int(file) - 97 : 104 - Int(file)
        let row = orientation == .white ? 8 - rank : rank - 1
        return CGRect(x: CGFloat(column) * size, y: CGFloat(row) * size, width: size, height: size)
    }
    static func center(_ square: String, _ orientation: Side, _ size: CGFloat) -> CGPoint? {
        rect(square, orientation, size).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    /// Top trailing: the rank digit sits top leading and the file letter bottom trailing.
    private func cornerBadge(_ symbol: Symbol, in rect: CGRect, bottomLeading: Bool = false, context: GraphicsContext) {
        guard let image = context.resolveSymbol(id: symbol) else { return }
        let inset = badgeSize / 2 + 1
        let point = bottomLeading ? CGPoint(x: rect.minX + inset, y: rect.maxY - inset) : CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        context.draw(image, at: point)
    }
    private func drawTint(_ mark: SquareMark, in rect: CGRect, context: GraphicsContext) {
        switch mark {
        case .quickScan:
            // The notch: a solid triangle in the top trailing corner.
            let notch = size * 0.3
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
            path.closeSubpath()
            context.fill(path, with: .color(BoardPalette.markHighlight))
        case .red:
            cornerBadge(.red, in: rect, context: context)
        case .orange:
            let width = size * 0.08
            context.stroke(Path(rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(BoardPalette.markOrange), lineWidth: width)
            cornerBadge(.orange, in: rect, context: context)
        }
    }
    private func drawRing(_ ring: RingStyle, in rect: CGRect, context: GraphicsContext) {
        let width = max(2, size * 0.07)
        let circle = Path(ellipseIn: rect.insetBy(dx: width / 2 + size * 0.04, dy: width / 2 + size * 0.04))
        switch ring {
        case .correct:
            context.stroke(circle, with: .color(BoardPalette.ringCorrect), lineWidth: width)
            cornerBadge(.correct, in: rect, bottomLeading: true, context: context)
        case .missed:
            context.stroke(circle, with: .color(BoardPalette.ringMissed),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [size * 0.1, size * 0.09]))
        case .extra:
            context.stroke(circle, with: .color(BoardPalette.ringExtra), lineWidth: width)
            cornerBadge(.extra, in: rect, bottomLeading: true, context: context)
        }
    }
    private func drawArrow(_ arrow: BoardArrow, context: GraphicsContext) {
        guard arrow.from != arrow.to, let start = Self.center(arrow.from, orientation, size),
              let end = Self.center(arrow.to, orientation, size) else { return }
        let dx = end.x - start.x, dy = end.y - start.y, length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length, uy = dy / length
        let head = size * 0.42, shaft = size * 0.15
        // The shaft stops at the head's base, so a dashed shaft doesn't show through the head.
        let base = CGPoint(x: end.x - ux * head, y: end.y - uy * head)
        var line = Path(); line.move(to: start); line.addLine(to: base)
        let color = arrow.side == .own ? BoardPalette.arrowOwn : BoardPalette.arrowTheirs
        let style = arrow.side == .own ? StrokeStyle(lineWidth: shaft, lineCap: .round)
            : StrokeStyle(lineWidth: shaft, lineCap: .butt, dash: [shaft * 1.2, shaft * 0.9])
        context.stroke(line, with: .color(color.opacity(0.85)), style: style)
        var tip = Path()
        tip.move(to: end)
        tip.addLine(to: CGPoint(x: base.x - uy * head / 2, y: base.y + ux * head / 2))
        tip.addLine(to: CGPoint(x: base.x + uy * head / 2, y: base.y - ux * head / 2))
        tip.closeSubpath()
        context.fill(tip, with: .color(color.opacity(0.85)))
    }
}

/// A symbol on a filled circle with a white edge, so it reads over a piece or either square colour.
private struct Badge: View {
    let systemImage: String
    let fill: Color
    let foreground: Color
    let size: CGFloat
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.6, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: max(1, size * 0.08)))
    }
}
