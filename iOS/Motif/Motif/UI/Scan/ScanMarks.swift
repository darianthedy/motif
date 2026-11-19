import Foundation

/// What the user has marked in the step on screen: quick-scan squares, targets or arrows. One
/// value, so a change is one undo step and the board's annotations are built in one place.
struct ScanMarks: Equatable, Sendable {
    /// Quick scan.
    var squares: Set<String> = []
    /// Targets.
    var targets: [String: ScanTargetMark] = [:]
    /// Checks, captures and threats, in the order drawn: `BoardView.onArrowTap` gives an index.
    var arrows: [BoardArrow] = []

    var red: Set<String> { squares(marked: .red) }
    var orange: Set<String> { squares(marked: .orange) }
    var dots: Set<String> { squares(marked: .dot) }
    /// Arrows as from + to squares, as `ScanGrader.gradeArrows` takes them.
    var lines: Set<String> { Set(arrows.map(\.line)) }

    mutating func toggle(_ square: String) {
        if squares.contains(square) { squares.remove(square) } else { squares.insert(square) }
    }

    /// One tap in the target step; `kind` says what the square can be marked.
    mutating func cycleTarget(_ square: String, _ kind: ScanTargetMark.Square) {
        targets[square] = ScanTargetMark.next(after: targets[square], on: kind)
    }

    /// An arrow from `from` to `to`. Drawing one that's already there takes it away again, as on
    /// most chess boards.
    mutating func drawArrow(from: String, to: String, side: BoardArrow.Side) {
        guard from != to else { return }
        if let index = arrows.firstIndex(where: { $0.from == from && $0.to == to }) { arrows.remove(at: index) }
        else { arrows.append(BoardArrow(from: from, to: to, side: side)) }
    }

    mutating func removeArrow(at index: Int) {
        guard arrows.indices.contains(index) else { return }
        arrows.remove(at: index)
    }

    /// The marks as the board draws them while the step is played.
    var annotations: BoardAnnotations {
        var annotations = BoardAnnotations()
        for square in squares { annotations.tints[square] = .quickScan }
        for (square, mark) in targets {
            switch mark {
            case .red: annotations.tints[square] = .red
            case .orange: annotations.tints[square] = .orange
            case .dot: annotations.dots.insert(square)
            }
        }
        annotations.arrows = arrows
        return annotations
    }

    private func squares(marked mark: ScanTargetMark) -> Set<String> {
        Set(targets.filter { $0.value == mark }.keys)
    }
}
