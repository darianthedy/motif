import SwiftUI

struct BoardView: View {
    let fen: String
    var orientation = Side.white
    var interactive = true
    var placing: Side?
    var highlight: (from: String, to: String)?
    var highlightColor = Color.blue
    var shakeKey = 0
    var coordinates = true
    var onMove: (Uci) -> Void = { _ in }
    var onPlace: (Placement) -> Void = { _ in }
    /// A pending promotion or placement goes here, for the screen's `PieceRow` in its layout:
    /// pickers are never drawn over the board (decision 17). Setting it to nil cancels it.
    var pending: Binding<BoardPending?>?
    /// Only `.play` selects and moves pieces; the other modes only call back (Scan plan §4).
    var mode = BoardMode.play
    var annotations = BoardAnnotations()
    var onSquare: (String) -> Void = { _ in }
    /// `.markTargets`: one drag over several squares, in the order crossed.
    var onSquares: ([String]) -> Void = { _ in }
    /// `.drawArrows`: an arrow dragged from a piece to a square.
    var onArrow: (String, String) -> Void = { _, _ in }
    @State private var interaction: BoardInteraction
    @State private var dragging: String?
    /// Where the finger is, read only by the lifted piece: a drag frame redraws that piece,
    /// not the 64 squares.
    @State private var dragPoint = DragPoint()
    @State private var moved = 0
    /// The piece currently sliding to its square. A token per move restarts the slide.
    @State private var slide: Slide?
    /// A drag already put the piece where it lands, so its move must not slide.
    @State private var dropped: (from: String, to: String)?
    /// Counts marking taps, for the selection haptic.
    @State private var marked = 0
    /// `.drawArrows`: the piece an arrow is being dragged from; the finger is `dragPoint`.
    @State private var arrowDrag: String?
    /// `.markTargets`: the squares a drag has crossed so far, shown until it ends.
    @State private var sweep: [String] = []
    /// With Reduce Motion a move appears in place instead of sliding (Scan plan §4).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(fen: String, orientation: Side = .white, interactive: Bool = true, placing: Side? = nil,
         highlight: (from: String, to: String)? = nil, highlightColor: Color = .blue, shakeKey: Int = 0, coordinates: Bool = true,
         onMove: @escaping (Uci) -> Void = { _ in }, onPlace: @escaping (Placement) -> Void = { _ in },
         pending: Binding<BoardPending?>? = nil,
         mode: BoardMode = .play, annotations: BoardAnnotations = BoardAnnotations(), onSquare: @escaping (String) -> Void = { _ in },
         onSquares: @escaping ([String]) -> Void = { _ in }, onArrow: @escaping (String, String) -> Void = { _, _ in }) {
        self.fen = fen; self.orientation = orientation; self.interactive = interactive; self.placing = placing
        self.highlight = highlight; self.highlightColor = highlightColor; self.shakeKey = shakeKey; self.coordinates = coordinates; self.onMove = onMove; self.onPlace = onPlace
        self.pending = pending; self.mode = mode; self.annotations = annotations; self.onSquare = onSquare
        self.onSquares = onSquares; self.onArrow = onArrow
        _interaction = State(initialValue: BoardInteraction(fen: fen, interactive: interactive, placing: placing))
    }
    private static let whiteOrder = (1...8).reversed().flatMap { rank in "abcdefgh".map { "\($0)\(rank)" } }
    private static let blackOrder = (1...8).flatMap { rank in "hgfedcba".map { "\($0)\(rank)" } }
    fileprivate static let squareIndex = Dictionary(uniqueKeysWithValues: Board.squares.enumerated().map { ($1, $0) })
    private var ordered: [String] { orientation == .white ? Self.whiteOrder : Self.blackOrder }
    var body: some View {
        // Parse the position and generate the selection's targets once per
        // render, not once per square: dragging re-renders on every frame.
        let snapshot = Snapshot(Board.snapshot(fen))
        let targets = interaction.targets
        let order = ordered
        let lit = Self.highlighted(highlight, snapshot: snapshot)
        GeometryReader { geometry in
            let size = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { column in
                                let index = row * 8 + column
                                squareView(order[index], index: index, size: size, piece: snapshot[order[index]],
                                           turn: snapshot.turn, target: targets[order[index]], lit: lit.contains(order[index]))
                            }
                        }
                    }
                }
                if !annotations.isEmpty {
                    BoardOverlay(annotations: annotations, orientation: orientation, size: size)
                }
                if let arrowDrag, let start = BoardOverlay.center(arrowDrag, orientation, size) {
                    ArrowPreview(start: start, point: dragPoint, size: size,
                                 color: snapshot[arrowDrag]?.color == orientation ? BoardPalette.arrowOwn : BoardPalette.arrowTheirs)
                }
                if let slide, let piece = snapshot[slide.to], let from = order.firstIndex(of: slide.from), let to = order.firstIndex(of: slide.to) {
                    SlidingPiece(piece: piece, size: size,
                                 start: CGPoint(x: CGFloat(from % 8) * size, y: CGFloat(from / 8) * size),
                                 end: CGPoint(x: CGFloat(to % 8) * size, y: CGFloat(to / 8) * size)) {
                        if self.slide?.token == slide.token { self.slide = nil }
                    }.id(slide.token)
                }
                if let dragging, let piece = snapshot[dragging] {
                    DraggedPiece(piece: piece, size: size, point: dragPoint)
                }
            }.coordinateSpace(.named("motif-board"))
        }.aspectRatio(1, contentMode: .fit)
            .sensoryFeedback(.selection, trigger: interaction.selected)
            .sensoryFeedback(.impact(weight: .light), trigger: moved)
            .sensoryFeedback(.error, trigger: shakeKey)
            .sensoryFeedback(.selection, trigger: marked)
            .onChange(of: fen) { old, next in
                interaction.reset(next); dragging = nil; clearMarking()
                let wasDropped = dropped; dropped = nil
                guard !reduceMotion, let motion = highlight, motion.from != motion.to,
                      Board.pieceAt(next, motion.to) != nil, Board.pieceAt(old, motion.from) != nil,
                      !(wasDropped?.from == motion.from && wasDropped?.to == motion.to) else { slide = nil; return }
                slide = Slide(from: motion.from, to: motion.to, token: (slide?.token ?? 0) + 1)
            }
            .onChange(of: interactive) { _, next in
                interaction.interactive = next
                if !next { interaction.cancel(); dragging = nil; clearMarking() }
            }
            .onChange(of: mode) { _, _ in interaction.cancel(); dragging = nil; clearMarking() }
            .onChange(of: placing) { _, next in interaction.placing = next; interaction.cancel() }
            .onChange(of: interaction.pending) { _, next in
                guard let pending, pending.wrappedValue != next else { return }
                pending.wrappedValue = next
            }
            .onChange(of: pending?.wrappedValue ?? nil) { _, next in
                if next == nil, interaction.pending != nil { interaction.cancel() }
            }
    }
    /// The last move's squares; a castling's rook squares too, as castling moves both pieces
    /// (playtest 4: only the king's were lit).
    private static func highlighted(_ highlight: (from: String, to: String)?, snapshot: Snapshot) -> Set<String> {
        guard let highlight else { return [] }
        var lit: Set<String> = [highlight.from, highlight.to]
        let from = highlight.from, to = highlight.to
        guard from.count == 2, to.count == 2, from.last == to.last, snapshot[to]?.type == .king || snapshot[from]?.type == .king,
              let fromFile = from.first?.asciiValue, let toFile = to.first?.asciiValue, abs(Int(fromFile) - Int(toFile)) == 2
        else { return lit }
        let rank = String(to.suffix(1)), kingside = toFile > fromFile
        lit.insert((kingside ? "h" : "a") + rank)
        lit.insert((kingside ? "f" : "d") + rank)
        return lit
    }
    private func squareView(_ square: String, index: Int, size: CGFloat, piece: Board.Piece?, turn: Side?, target: Board.Target?, lit: Bool) -> some View {
        let selected = interaction.selected == square || interaction.pending == .placement(square)
        let light = (index / 8 + index % 8) % 2 == 0
        return Button { tapped(square, piece: piece) } label: {
            ZStack {
                (light ? BoardPalette.lightSquare : BoardPalette.darkSquare)
                if lit { highlightColor.opacity(0.4) }
                if selected { Color.yellow.opacity(0.55) }
                if sweep.contains(square) { Color.yellow.opacity(0.35) }
                // A mark's fill sits under the piece so the piece stays legible; its shape is in `BoardOverlay`.
                if let mark = annotations.tints[square], let fill = mark.fill(faded: annotations.faded.contains(square)) { fill }
                // A ghost stands in for the piece on its square: the move isn't played yet.
                if let piece, dragging != square, slide?.to != square, annotations.ghost?.square != square {
                    PieceImage(type: piece.type, color: piece.color).padding(2)
                }
                if let ghost = annotations.ghost, ghost.square == square {
                    PieceImage(type: ghost.piece.type, color: ghost.piece.color).padding(2).opacity(0.45)
                }
                if let target {
                    if target.capture { Circle().stroke(.black.opacity(0.28), lineWidth: 5).padding(3) }
                    else { Circle().fill(.black.opacity(0.28)).frame(width: size * 0.24) }
                }
                if coordinates {
                    VStack {
                        HStack { if index % 8 == 0 { Text(String(square.suffix(1))) }; Spacer() }
                        Spacer()
                        HStack { Spacer(); if index / 8 == 7 { Text(String(square.prefix(1))) } }
                    }.font(.system(size: max(9, size * 0.2), weight: .medium)).foregroundStyle(light ? Color.brown : BoardPalette.lightSquare).padding(2)
                }
            }.frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("square-" + square)
            .accessibilityLabel(square + (piece.map { ", \($0.color == .white ? "White" : "Black") \($0.type.name)" } ?? ", empty")
                                + (annotations.accessibilityDescription(square).map { ", " + $0 } ?? ""))
            .accessibilityAddTraits(selected || isMarked(square) ? .isSelected : [])
            .accessibilityHint(interactive ? hint(square, piece: piece) : "")
            // In `.drawArrows` the drag takes every touch, taps too, so a tap that isn't an arrow
            // marks the square; VoiceOver's activation still reaches the Button.
            .highPriorityGesture(DragGesture(minimumDistance: mode == .drawArrows ? 0 : 8, coordinateSpace: .named("motif-board"))
                .onChanged { value in dragChanged(square, piece: piece, turn: turn, value: value, size: size) }
                .onEnded { value in dragEnded(square, piece: piece, value: value, size: size) },
                including: interactive && placing == nil ? .all : .none)
    }
    private func isMarked(_ square: String) -> Bool {
        // An earlier step's dimmed mark isn't this step's: not selected.
        guard !annotations.faded.contains(square) else { return false }
        switch mode {
        case .play: return false
        case .markSquares: return annotations.tints[square] != nil
        case .markTargets, .drawArrows: return annotations.tints[square] != nil || annotations.dots.contains(square)
        }
    }
    private func hint(_ square: String, piece: Board.Piece?) -> String {
        switch mode {
        case .play: ""
        case .markSquares: "Marks or unmarks the square."
        case .markTargets: piece == nil ? "Marks the square red, then orange, then a dot, then clears it." : "Marks the piece red, then orange, then clears it."
        case .drawArrows:
            piece == nil ? "Marks the square." : "Marks the piece red, then orange, then clears it. Drag to draw an arrow."
        }
    }
    private func square(at point: CGPoint, size: CGFloat) -> String? {
        let x = Int(floor(point.x / size)), y = Int(floor(point.y / size))
        return (0..<8).contains(x) && (0..<8).contains(y) ? ordered[y * 8 + x] : nil
    }
    private func dragChanged(_ square: String, piece: Board.Piece?, turn: Side?, value: DragGesture.Value, size: CGFloat) {
        switch mode {
        case .play:
            guard interactive, placing == nil, let piece, piece.color == turn, interaction.pending == nil else { return }
            if dragging != square { dragging = square }
            dragPoint.value = value.location
        // The drag is still taken, and does nothing: left to the Button, a drag that ended on
        // another square counted as a tap on the first (Scan plan §4).
        case .markSquares: return
        case .markTargets:
            if sweep.isEmpty { sweep = [square] }
            if let over = self.square(at: value.location, size: size), !sweep.contains(over) { sweep.append(over) }
        case .drawArrows:
            // Under 8 pt it's still a tap.
            guard piece != nil, arrowDrag == square || hypot(value.translation.width, value.translation.height) >= 8 else { return }
            if arrowDrag != square { arrowDrag = square }
            dragPoint.value = value.location
        }
    }
    private func dragEnded(_ square: String, piece: Board.Piece?, value: DragGesture.Value, size: CGFloat) {
        switch mode {
        case .play:
            guard dragging == square else { return }
            dragging = nil
            let to = self.square(at: value.location, size: size)
            if let to { dropped = (from: square, to: to) } else { dropped = nil }
            emit(interaction.drop(square, to))
        case .markSquares: return
        case .markTargets:
            let swept = sweep; sweep = []
            guard interactive, !swept.isEmpty else { return }
            marked += 1; onSquares(swept)
        case .drawArrows:
            if arrowDrag == square {
                arrowDrag = nil
                guard interactive, let to = self.square(at: value.location, size: size), to != square else { return }
                marked += 1; onArrow(square, to)
            } else if hypot(value.translation.width, value.translation.height) < 8 {
                tapped(square, piece: piece, at: value.location, size: size)
            }
        }
    }
    private func clearMarking() { arrowDrag = nil; sweep = [] }
    /// `.play` goes through `BoardInteraction`; any other mode only calls back, so no piece moves.
    /// In `.drawArrows` a tap marks the square, as in `.markTargets`: arrows are drawn by drag only.
    private func tapped(_ square: String, piece: Board.Piece?, at point: CGPoint? = nil, size: CGFloat = 0) {
        switch mode {
        case .play: dropped = nil; emit(interaction.tap(square))
        case .markSquares, .markTargets, .drawArrows:
            guard interactive else { return }
            marked += 1; onSquare(square)
        }
    }
    private func emit(_ output: BoardOutput?) {
        guard let output else { return }; moved += 1
        switch output { case .move(let move): onMove(move); case .placement(let placement): onPlace(placement) }
    }
}

private struct Slide { var from: String; var to: String; var token: Int }

@Observable @MainActor private final class DragPoint { var value = CGPoint.zero }

/// The arrow being dragged, from its piece to the finger. Reads the drag point itself, so a drag
/// frame redraws only this.
private struct ArrowPreview: View {
    let start: CGPoint
    let point: DragPoint
    let size: CGFloat
    let color: Color
    var body: some View {
        Canvas { context, _ in
            guard let shape = BoardArrowShape(from: start, to: point.value, size: size) else { return }
            shape.fill(side: .own, color: color.opacity(0.6), context: context)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The lifted piece under the finger, slightly enlarged.
private struct DraggedPiece: View {
    let piece: Board.Piece
    let size: CGFloat
    let point: DragPoint
    var body: some View {
        PieceImage(type: piece.type, color: piece.color).frame(width: size * 1.12, height: size * 1.12)
            .shadow(radius: 5).position(x: point.value.x, y: point.value.y - size * 0.25).allowsHitTesting(false)
    }
}

private struct Snapshot {
    let cells: [Board.Piece?]
    let turn: Side?
    init(_ value: (cells: [Board.Piece?], turn: Side?)) { cells = value.cells; turn = value.turn }
    subscript(square: String) -> Board.Piece? {
        guard let index = BoardView.squareIndex[square], cells.indices.contains(index) else { return nil }
        return cells[index]
    }
}

/// Drawn above every square, so the piece never passes underneath a
/// neighbour. Starts at the origin on appear, then eases into place.
private struct SlidingPiece: View {
    let piece: Board.Piece
    let size: CGFloat
    let start: CGPoint
    let end: CGPoint
    let finished: () -> Void
    @State private var arrived = false
    var body: some View {
        let point = arrived ? end : start
        PieceImage(type: piece.type, color: piece.color).padding(2).frame(width: size, height: size)
            .offset(x: point.x, y: point.y).allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: Double(SLIDE_MS) / 1000)) { arrived = true } completion: { finished() }
            }
    }
}

#Preview { BoardView(fen: Board.defaultPosition).padding() }

#if DEBUG
struct BoardSampleView: View {
    @State private var fen = Board.defaultPosition
    @State private var pending: BoardPending?
    var body: some View {
        VStack {
            BoardView(fen: fen, onMove: play, pending: $pending)
            if case .promotion(let from, let to) = pending {
                PieceRow(color: Board.turnOf(fen) ?? .white, choose: { piece in
                    pending = nil
                    if let move = BoardInteraction.promotion(fen, from, to, piece) { play(move) }
                }, cancel: { pending = nil })
            }
            Text("Tap or drag a piece").foregroundStyle(.motifSecondary); Spacer()
        }.padding().navigationTitle("Board")
    }
    private func play(_ move: Uci) { if let next = Board.applyUci(fen, move) { fen = next } }
}
#endif
