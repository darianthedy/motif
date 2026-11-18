import SwiftUI

#if DEBUG
/// The `scan-board` debug route (Scan plan S03), like `board`: the sample puzzle's position in
/// `.markSquares`, graded against its quick scan; in `.markTargets` (`scan-board:targets`) and
/// `.drawArrows` (`scan-board:arrows`); and every mark shape at once (`scan-board:shapes`) for
/// screenshots.
struct ScanBoardSampleView: View {
    enum Page: String, CaseIterable {
        case mark = "Mark", targets = "Targets", arrows = "Arrows", shapes = "Shapes"
        /// `scan-board:targets` → `.targets`; plain `scan-board` → `.mark`.
        init(route: String) {
            let name = route.split(separator: ":").dropFirst().first.map(String.init) ?? ""
            self = Self.allCases.first { $0.rawValue.lowercased() == name } ?? .mark
        }
    }
    @State var page: Page
    @State private var tapped: Set<String> = []
    @State private var graded: ScanMarkGrade?
    @State private var marks = ScanMarks()
    var body: some View {
        VStack {
            Picker("Page", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("scan-board-page")
            switch page {
            case .mark:
                BoardView(fen: Self.fen, orientation: .white, interactive: graded == nil,
                          highlight: (from: Self.lastMove.from, to: Self.lastMove.to),
                          mode: .markSquares, annotations: markAnnotations, onSquare: toggle)
                Text(graded == nil ? "Tap the squares the last move changed" : "\(tapped.count) marked")
                    .foregroundStyle(.motifSecondary).accessibilityIdentifier("scan-board-status")
                Button(graded == nil ? "Check" : "Clear", systemImage: graded == nil ? "checkmark" : "arrow.counterclockwise") {
                    if graded == nil { graded = ScanGrader.gradeQuickScan(tapped: tapped, answer: Self.answer) }
                    else { graded = nil; tapped = [] }
                }.buttonStyle(.glassProminent).accessibilityIdentifier("scan-board-check")
            case .targets:
                BoardView(fen: Self.fen, orientation: .white, mode: .markTargets, annotations: marks.annotations,
                          onSquare: { cycle([$0]) }, onSquares: cycle)
                Text("Tap or drag: orange, red, clear; empty squares then a dot").foregroundStyle(.motifSecondary)
            case .arrows:
                BoardView(fen: Self.fen, orientation: .white, mode: .drawArrows, annotations: marks.annotations,
                          onArrow: { from, to in
                              let side: BoardArrow.Side = Board.pieceAt(Self.fen, from)?.color == .white ? .own : .theirs
                              marks.drawArrow(from: from, to: to, side: side)
                          }, onArrowTap: { marks.removeArrow(at: $0) })
                ScanArrowList(arrows: marks.arrows, fen: Self.fen) { marks.removeArrow(at: $0) }
            case .shapes:
                BoardView(fen: Self.fen, orientation: .white, interactive: false, mode: .markSquares, annotations: Self.shapes)
                Text("Highlight, red, orange, dots, rings, arrows and a ghost").foregroundStyle(.motifSecondary)
            }
            Spacer()
        }.padding().navigationTitle("Scan Board")
            .onChange(of: page) { marks = ScanMarks(); tapped = []; graded = nil }
    }
    private func cycle(_ squares: [String]) {
        for square in squares { marks.cycleTarget(square, piece: Board.pieceAt(Self.fen, square) != nil) }
    }
    private func toggle(_ square: String) {
        if tapped.contains(square) { tapped.remove(square) } else { tapped.insert(square) }
    }
    private var markAnnotations: BoardAnnotations {
        var annotations = BoardAnnotations()
        for square in tapped { annotations.tints[square] = .quickScan }
        if let graded {
            for square in tapped where !graded.extra.contains(square) { annotations.rings[square] = .correct }
            for square in graded.extra { annotations.rings[square] = .extra }
            for square in graded.missed { annotations.rings[square] = .missed }
        }
        return annotations
    }
    /// The format sample's first puzzle (`samples/scan-sample.json`), after 3…Nf6.
    static let fenBefore = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"
    static let lastMove = (from: "g8", to: "f6")
    static let fen = Board.applyUci(fenBefore, try! makeMove("g8", "f6")) ?? fenBefore
    static let answer = ScanAnswer(flagged: true, quickScan: [ScanSquare(square: "e4", kind: .attacked)],
                                   moves: [:])
    static let shapes = BoardAnnotations(
        tints: ["e4": .quickScan, "f7": .red, "e5": .orange],
        dots: ["g7", "d5"],
        rings: ["e4": .correct, "c6": .missed, "a7": .extra],
        arrows: [BoardArrow(from: "f3", to: "g5", side: .own, style: .correct), BoardArrow(from: "f6", to: "e4", side: .theirs),
                 BoardArrow(from: "c4", to: "f7", side: .own, style: .missed), BoardArrow(from: "c6", to: "d4", side: .theirs, style: .missed)],
        ghost: BoardGhost(square: "g5", piece: Board.Piece(square: "g5", type: .knight, color: .white)))
}
#endif
