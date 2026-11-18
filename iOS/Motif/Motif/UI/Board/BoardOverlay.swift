import SwiftUI

/// Mark shapes, dots, rings and arrows in one `Canvas` pass above the squares (Scan plan §4). It
/// takes no touches: the squares under it stay the buttons, and `arrowHit` finds a tapped arrow.
/// Every mark has a shape as well as a colour, so none relies on colour alone. Tint fills sit
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
                // A carried quick-scan notch keeps its full violet: with no fill under it, a dimmed
                // notch would read pink, like a red target's tint.
                drawTint(mark, in: rect, context: mark == .quickScan ? context : faded(square, context))
            }
            for square in annotations.dots {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                let dot = rect.insetBy(dx: size * 0.37, dy: size * 0.37), context = faded(square, context)
                context.fill(Path(ellipseIn: dot), with: .color(BoardPalette.markDot))
                context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: max(1, size * 0.03))
            }
            for (square, ring) in annotations.rings {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                drawRing(ring, in: rect, context: context)
            }
            for arrow in annotations.arrows { drawArrow(arrow, context: context) }
            // Badges go last, over rings and arrows: an arrowhead ending on a target never hides its
            // symbol, and a graded target still shows its colour's.
            for (square, ring) in annotations.rings {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                switch ring {
                case .correct: cornerBadge(.correct, in: rect, bottomLeading: true, context: context)
                case .extra: cornerBadge(.extra, in: rect, bottomLeading: true, context: context)
                case .missed: break
                }
            }
            for (square, mark) in annotations.tints {
                guard let rect = Self.rect(square, orientation, size) else { continue }
                switch mark {
                case .quickScan: break
                case .red: cornerBadge(.red, in: rect, context: faded(square, context))
                case .orange: cornerBadge(.orange, in: rect, context: faded(square, context))
                }
            }
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
    /// An earlier step's mark is drawn at reduced opacity: still there to build on, plainly not
    /// this step's input.
    private func faded(_ square: String, _ context: GraphicsContext) -> GraphicsContext {
        guard annotations.faded.contains(square) else { return context }
        var copy = context
        copy.opacity = 0.45
        return copy
    }
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
            break
        case .orange:
            let width = size * 0.08
            context.stroke(Path(rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(BoardPalette.markOrange), lineWidth: width)
        }
    }
    /// The ring alone; its badge is drawn with the others, above the arrows.
    private func drawRing(_ ring: RingStyle, in rect: CGRect, context: GraphicsContext) {
        let width = max(2, size * 0.07)
        let circle = Path(ellipseIn: rect.insetBy(dx: width / 2 + size * 0.04, dy: width / 2 + size * 0.04))
        switch ring {
        case .correct:
            context.stroke(circle, with: .color(BoardPalette.ringCorrect), lineWidth: width)
        case .missed:
            context.stroke(circle, with: .color(BoardPalette.ringMissed),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [size * 0.1, size * 0.09]))
        case .extra:
            context.stroke(circle, with: .color(BoardPalette.ringExtra), lineWidth: width)
        }
    }
    private func drawArrow(_ arrow: BoardArrow, context: GraphicsContext) {
        guard let start = Self.center(arrow.from, orientation, size), let end = Self.center(arrow.to, orientation, size),
              let shape = BoardArrowShape(from: start, to: end, size: size) else { return }
        let color = (arrow.side == .own ? BoardPalette.arrowOwn : BoardPalette.arrowTheirs).opacity(0.85)
        switch arrow.style {
        case .drawn, .correct:
            shape.fill(side: arrow.side, color: color, context: context)
            if arrow.style == .correct, let badge = context.resolveSymbol(id: Symbol.correct) {
                context.draw(badge, at: CGPoint(x: (start.x + shape.base.x) / 2, y: (start.y + shape.base.y) / 2))
            }
        case .missed:
            // An outline, dashed for their side as the filled arrow's shaft is.
            let width = max(2, size * 0.05)
            context.stroke(shape.outline, with: .color(color),
                           style: StrokeStyle(lineWidth: width, lineJoin: .round,
                                              dash: arrow.side == .own ? [] : [size * 0.12, size * 0.08]))
        }
    }

    /// The arrow a tap at `point` lands on, nearest first: within `tolerance` of its shaft (12 pt,
    /// Scan plan §4), but not on the squares it joins, so their pieces stay tappable to start
    /// another arrow. Nil when the tap is on no arrow.
    static func arrowHit(_ point: CGPoint, arrows: [BoardArrow], orientation: Side, size: CGFloat,
                         tolerance: CGFloat = 12) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, arrow) in arrows.enumerated() {
            guard let a = center(arrow.from, orientation, size), let b = center(arrow.to, orientation, size), a != b else { continue }
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
            let distance = hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
            let fromEnds = min(hypot(point.x - a.x, point.y - a.y), hypot(point.x - b.x, point.y - b.y))
            guard distance <= tolerance + size * 0.075, fromEnds >= size * 0.35 else { continue }
            if best.map({ distance < $0.distance }) ?? true { best = (index, distance) }
        }
        return best?.index
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
