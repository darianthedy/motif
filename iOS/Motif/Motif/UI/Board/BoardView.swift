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
    @State private var motion: (from: String, to: String)?
    @State private var motionProgress = 1.0
    init(fen: String, orientation: Side = .white, interactive: Bool = true, placing: Side? = nil,
         highlight: (from: String, to: String)? = nil, shakeKey: Int = 0,
         onMove: @escaping (Uci) -> Void = { _ in }, onPlace: @escaping (Placement) -> Void = { _ in }) {
        self.fen = fen; self.orientation = orientation; self.interactive = interactive; self.placing = placing
        self.highlight = highlight; self.shakeKey = shakeKey; self.onMove = onMove; self.onPlace = onPlace
        _interaction = State(initialValue: BoardInteraction(fen: fen, interactive: interactive, placing: placing))
    }
    private var ordered: [String] { orientation == .white ? (1...8).reversed().flatMap { rank in "abcdefgh".map { "\($0)\(rank)" } } : (1...8).flatMap { rank in "hgfedcba".map { "\($0)\(rank)" } } }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 0), count: 8), spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element) { index, square in
                        squareView(square, index: index, size: size)
                    }
                }
                if let dragging, let piece = Board.pieceAt(fen, dragging) {
                    PieceImage(type: piece.type, color: piece.color).frame(width: size * 1.12, height: size * 1.12)
                        .shadow(radius: 5).position(x: dragPoint.x, y: dragPoint.y - size * 0.25).allowsHitTesting(false)
                }
                if let pending = interaction.pending {
                    Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { interaction.cancel() }
                    PiecePicker(title: pickerTitle(pending), choices: interaction.choices, color: placing ?? Board.turnOf(fen) ?? .white,
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
                motion = highlight
                if let motion, Board.pieceAt(next, motion.to) != nil, Board.pieceAt(old, motion.from) != nil {
                    motionProgress = 0
                    withAnimation(.easeOut(duration: 0.15)) { motionProgress = 1 }
                }
            }
            .onChange(of: interactive) { _, next in interaction.interactive = next; if !next { interaction.cancel(); dragging = nil } }
            .onChange(of: placing) { _, next in interaction.placing = next; interaction.cancel() }
    }
    private func squareView(_ square: String, index: Int, size: CGFloat) -> some View {
        let piece = Board.pieceAt(fen, square)
        let selected = interaction.selected == square || interaction.pending == .placement(square)
        let light = (index / 8 + index % 8) % 2 == 0
        return Button { emit(interaction.tap(square)) } label: {
            ZStack {
                (light ? Color(red: 0.94, green: 0.85, blue: 0.71) : Color(red: 0.71, green: 0.53, blue: 0.39))
                if highlight?.from == square || highlight?.to == square { Color.blue.opacity(0.4) }
                if selected { Color.yellow.opacity(0.55) }
                if let piece, dragging != square {
                    PieceImage(type: piece.type, color: piece.color).padding(2).offset(pieceOffset(square, size: size))
                }
                if let target = interaction.targets[square] {
                    if target.capture { Circle().stroke(.black.opacity(0.28), lineWidth: 5).padding(3) }
                    else { Circle().fill(.black.opacity(0.28)).frame(width: size * 0.24) }
                }
                VStack {
                    HStack { if index % 8 == 0 { Text(String(square.suffix(1))) }; Spacer() }
                    Spacer()
                    HStack { Spacer(); if index / 8 == 7 { Text(String(square.prefix(1))) } }
                }.font(.system(size: max(9, size * 0.2), weight: .medium)).foregroundStyle(light ? Color.brown : Color(red: 0.94, green: 0.85, blue: 0.71)).padding(2)
            }.frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("square-" + square)
            .accessibilityLabel(square + (piece.map { ", \($0.color == .white ? "White" : "Black") \($0.type.name)" } ?? ", empty"))
            .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("motif-board"))
                .onChanged { value in
                    guard interactive, placing == nil, piece?.color == Board.turnOf(fen), piece != nil, interaction.pending == nil else { return }
                    dragging = square; dragPoint = value.location
                }
                .onEnded { value in
                    guard dragging == square else { return }
                    dragging = nil
                    let x = Int(floor(value.location.x / size)), y = Int(floor(value.location.y / size))
                    let to = (0..<8).contains(x) && (0..<8).contains(y) ? ordered[y * 8 + x] : nil
                    emit(interaction.drop(square, to))
                }, including: interactive && placing == nil ? .all : .none)
    }
    private func pieceOffset(_ square: String, size: CGFloat) -> CGSize {
        guard let motion, motion.to == square, let from = ordered.firstIndex(of: motion.from), let to = ordered.firstIndex(of: motion.to) else { return .zero }
        return CGSize(width: CGFloat(from % 8 - to % 8) * size * (1 - motionProgress), height: CGFloat(from / 8 - to / 8) * size * (1 - motionProgress))
    }
    private func pickerTitle(_ pending: BoardPending) -> String {
        switch pending { case .promotion: "Promote to"; case .placement(let square): "Add on " + square }
    }
    private func emit(_ output: BoardOutput?) {
        guard let output else { return }; moved += 1
        switch output { case .move(let move): onMove(move); case .placement(let placement): onPlace(placement) }
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
