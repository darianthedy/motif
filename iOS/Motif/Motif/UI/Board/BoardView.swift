import SwiftUI

struct BoardView: View {
    let fen: String
    var orientation = Side.white
    var interactive = true
    var placing: Side?
    var highlight: (from: String, to: String)?
    var shakeKey = 0
    var onMove: (Uci) -> Void = { _ in }
    var onPlace: (Placement) -> Void = { _ in }
    @State private var interaction: BoardInteraction
    @State private var dragging: String?
    @State private var dragPoint = CGPoint.zero
    @State private var moved = 0
    /// The piece currently sliding to its square. A token per move restarts the slide.
    @State private var slide: Slide?
    /// A drag already put the piece where it lands, so its move must not slide.
    @State private var dropped: (from: String, to: String)?
    init(fen: String, orientation: Side = .white, interactive: Bool = true, placing: Side? = nil,
         highlight: (from: String, to: String)? = nil, shakeKey: Int = 0,
         onMove: @escaping (Uci) -> Void = { _ in }, onPlace: @escaping (Placement) -> Void = { _ in }) {
        self.fen = fen; self.orientation = orientation; self.interactive = interactive; self.placing = placing
        self.highlight = highlight; self.shakeKey = shakeKey; self.onMove = onMove; self.onPlace = onPlace
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
        GeometryReader { geometry in
            let size = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { column in
                                let index = row * 8 + column
                                squareView(order[index], index: index, size: size, piece: snapshot[order[index]],
                                           turn: snapshot.turn, target: targets[order[index]])
                            }
                        }
                    }
                }
                if let slide, let piece = snapshot[slide.to], let from = order.firstIndex(of: slide.from), let to = order.firstIndex(of: slide.to) {
                    SlidingPiece(piece: piece, size: size,
                                 start: CGPoint(x: CGFloat(from % 8) * size, y: CGFloat(from / 8) * size),
                                 end: CGPoint(x: CGFloat(to % 8) * size, y: CGFloat(to / 8) * size)) {
                        if self.slide?.token == slide.token { self.slide = nil }
                    }.id(slide.token)
                }
                if let dragging, let piece = snapshot[dragging] {
                    PieceImage(type: piece.type, color: piece.color).frame(width: size * 1.12, height: size * 1.12)
                        .shadow(radius: 5).position(x: dragPoint.x, y: dragPoint.y - size * 0.25).allowsHitTesting(false)
                }
                if let pending = interaction.pending {
                    Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { interaction.cancel() }
                    PiecePicker(title: pickerTitle(pending), choices: interaction.choices, color: placing ?? snapshot.turn ?? .white,
                                choose: { emit(interaction.choose($0)) }, cancel: { interaction.cancel() })
                        .frame(width: geometry.size.width, height: geometry.size.width)
                }
            }.coordinateSpace(name: "motif-board")
        }.aspectRatio(1, contentMode: .fit)
            .sensoryFeedback(.selection, trigger: interaction.selected)
            .sensoryFeedback(.impact(weight: .light), trigger: moved)
            .sensoryFeedback(.error, trigger: shakeKey)
            .onChange(of: fen) { old, next in
                interaction.reset(next); dragging = nil
                let wasDropped = dropped; dropped = nil
                guard let motion = highlight, motion.from != motion.to,
                      Board.pieceAt(next, motion.to) != nil, Board.pieceAt(old, motion.from) != nil,
                      !(wasDropped?.from == motion.from && wasDropped?.to == motion.to) else { slide = nil; return }
                slide = Slide(from: motion.from, to: motion.to, token: (slide?.token ?? 0) + 1)
            }
            .onChange(of: interactive) { _, next in interaction.interactive = next; if !next { interaction.cancel(); dragging = nil } }
            .onChange(of: placing) { _, next in interaction.placing = next; interaction.cancel() }
    }
    private func squareView(_ square: String, index: Int, size: CGFloat, piece: Board.Piece?, turn: Side?, target: Board.Target?) -> some View {
        let selected = interaction.selected == square || interaction.pending == .placement(square)
        let light = (index / 8 + index % 8) % 2 == 0
        return Button { dropped = nil; emit(interaction.tap(square)) } label: {
            ZStack {
                (light ? Self.lightSquare : Self.darkSquare)
                if highlight?.from == square || highlight?.to == square { Color.blue.opacity(0.4) }
                if selected { Color.yellow.opacity(0.55) }
                if let piece, dragging != square, slide?.to != square {
                    PieceImage(type: piece.type, color: piece.color).padding(2)
                }
                if let target {
                    if target.capture { Circle().stroke(.black.opacity(0.28), lineWidth: 5).padding(3) }
                    else { Circle().fill(.black.opacity(0.28)).frame(width: size * 0.24) }
                }
                VStack {
                    HStack { if index % 8 == 0 { Text(String(square.suffix(1))) }; Spacer() }
                    Spacer()
                    HStack { Spacer(); if index / 8 == 7 { Text(String(square.prefix(1))) } }
                }.font(.system(size: max(9, size * 0.2), weight: .medium)).foregroundStyle(light ? Color.brown : Self.lightSquare).padding(2)
            }.frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("square-" + square)
            .accessibilityLabel(square + (piece.map { ", \($0.color == .white ? "White" : "Black") \($0.type.name)" } ?? ", empty"))
            .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("motif-board"))
                .onChanged { value in
                    guard interactive, placing == nil, let piece, piece.color == turn, interaction.pending == nil else { return }
                    if dragging != square { dragging = square }
                    dragPoint = value.location
                }
                .onEnded { value in
                    guard dragging == square else { return }
                    dragging = nil
                    let x = Int(floor(value.location.x / size)), y = Int(floor(value.location.y / size))
                    let to = (0..<8).contains(x) && (0..<8).contains(y) ? ordered[y * 8 + x] : nil
                    if let to { dropped = (from: square, to: to) } else { dropped = nil }
                    emit(interaction.drop(square, to))
                }, including: interactive && placing == nil ? .all : .none)
    }
    private static let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.71)
    private static let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)
    private func pickerTitle(_ pending: BoardPending) -> String {
        switch pending { case .promotion: "Promote to"; case .placement(let square): "Add on " + square }
    }
    private func emit(_ output: BoardOutput?) {
        guard let output else { return }; moved += 1
        switch output { case .move(let move): onMove(move); case .placement(let placement): onPlace(placement) }
    }
}

private struct Slide { var from: String; var to: String; var token: Int }

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
                withAnimation(.easeOut(duration: 0.18)) { arrived = true } completion: { finished() }
            }
    }
}

#Preview { BoardView(fen: Board.defaultPosition).padding() }

#if DEBUG
struct BoardSampleView: View {
    @State private var fen = Board.defaultPosition
    var body: some View {
        VStack { BoardView(fen: fen, onMove: { if let next = Board.applyUci(fen, $0) { fen = next } }); Text("Tap or drag a piece").foregroundStyle(.secondary); Spacer() }.padding().navigationTitle("Board")
    }
}
#endif
