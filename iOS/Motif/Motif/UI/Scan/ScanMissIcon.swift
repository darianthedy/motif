import SwiftUI

/// A miss type's icon. The shape says the step (a square tile with the board's purple notch for
/// the quick scan, a rounded square for arrows), the colour the side, the glyph the kind. Never
/// colour alone: your arrows are solid, theirs dashed, as on the board.
struct ScanMissIcon: View {
    let type: ScanMissType
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    var body: some View {
        icon.frame(width: size, height: size).accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        switch type {
        case .quickScan(let kind):
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.16).fill(Color(.tertiarySystemFill))
                RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(Color(.separator), lineWidth: 0.5)
                if let name = Self.quickScanGlyph(kind) {
                    Image(systemName: name).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.primary)
                }
            }
            .overlay(alignment: .topTrailing) {
                Notch().fill(BoardPalette.markHighlight).frame(width: size * 0.36, height: size * 0.36)
                    .clipShape(UnevenRoundedRectangle(topTrailingRadius: size * 0.16))
            }
        case let .arrow(kind, side):
            let color = side == .own ? BoardPalette.arrowOwn : BoardPalette.arrowTheirs
            let shape = RoundedRectangle(cornerRadius: size * 0.28)
            ZStack {
                if side == .own {
                    shape.fill(color)
                } else {
                    shape.fill(color.opacity(0.14))
                    shape.strokeBorder(color, style: StrokeStyle(lineWidth: size * 0.09, dash: [size * 0.16, size * 0.1]))
                }
                Image(systemName: Self.arrowGlyph(kind))
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(side == .own ? .white : color)
            }
        }
    }

    /// Chess notation's own signs for check and capture; a crosshair for a threat.
    static func arrowGlyph(_ kind: ScanArrow.Kind) -> String {
        switch kind {
        case .check: "plus"
        case .capture: "xmark"
        case .threat: "scope"
        }
    }

    /// Nil for a missed square the answer doesn't name: the bare tile.
    static func quickScanGlyph(_ kind: ScanSquare.Kind?) -> String? {
        switch kind {
        case .attacked?: "bolt.fill"
        case .opened?: "arrow.up.left.and.arrow.down.right"
        case .undefended?: "shield.slash"
        case .unpinned?: "pin.slash"
        case .hanging?: "exclamationmark.triangle"
        case nil: nil
        }
    }
}

/// The quick scan's corner triangle, as `BoardOverlay` draws it.
private struct Notch: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
