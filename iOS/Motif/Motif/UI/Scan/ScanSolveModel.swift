import Foundation
import Observation

/// One scan puzzle, step by step (Scan plan §5): the board, the marks, the step's time and the
/// attempt being built. Grading is `ScanGrader`'s; this model only collects input and times it.
/// v1 order: the last move plays, the quick scan ends with Flag or No Flag, feedback, the move,
/// feedback. Nothing is saved until the view records `outcome`.
@Observable @MainActor final class ScanSolveModel {
    let puzzle: ScanPuzzle
    /// The side to move after the opponent's last move.
    let solver: Side
    private(set) var step = ScanStep.lastMove
    private(set) var fen: String
    private(set) var highlight: (from: String, to: String)?
    /// The quick scan's marked squares.
    private(set) var marks: Set<String> = []
    private(set) var flagCall: Bool?
    /// The graded step's feedback; nil while a step is being played.
    private(set) var feedback: ScanFeedback?
    /// When the running step started, for the elapsed-time display; nil between steps.
    private(set) var stepStarted: Date?
    /// Set once the move is graded: what the view records.
    private(set) var outcome: ScanOutcome?
    /// The step's marks in the order they changed, newest last: what Undo takes back.
    private(set) var history: [String] = []
    @ObservationIgnored private(set) var quickScanGrade: ScanMarkGrade?
    @ObservationIgnored private var steps = ScanSteps()
    @ObservationIgnored private let clock: any AnalysisClock
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var startedAt = Duration.zero
    @ObservationIgnored private var begun = false
    @ObservationIgnored private weak var undoManager: UndoManager?
    /// Kept so the move's result can say how much it gave away.
    @ObservationIgnored private let startFen: String

    init(_ puzzle: ScanPuzzle, clock: any AnalysisClock = SystemClock(), now: @escaping () -> Date = Date.init) {
        self.puzzle = puzzle; self.clock = clock; self.now = now
        fen = puzzle.fenBefore
        startFen = puzzle.startFen ?? puzzle.fenBefore
        solver = Board.turnOf(startFen) ?? .white
    }

    // MARK: Reading

    var canMark: Bool { step == .quickScan && feedback == nil }
    var canMove: Bool { step == .move }
    var canUndo: Bool { canMark && !history.isEmpty }
    var boardMode: BoardMode { step == .quickScan ? .markSquares : .play }
    var boardInteractive: Bool { canMark || canMove }
    /// The opponent's last move in SAN ("Nf6").
    var lastMoveSan: String { Board.sanFor(puzzle.fenBefore, puzzle.lastMove) ?? puzzle.lastMove.text }

    /// The step's one line of guidance.
    var prompt: String {
        switch step {
        case .lastMove: "Watch their move."
        case .quickScan: "Tap what \(lastMoveSan) attacks, opens or leaves undefended. Then call it."
        case .move: flagCall == true ? "Play your move, with the scan in mind." : "Play your move."
        default: ""
        }
    }

    /// Marks while scanning; after the call, rings for found, missed and extra squares; after a
    /// failed move, an arrow for the best one.
    var annotations: BoardAnnotations {
        var annotations = BoardAnnotations()
        switch step {
        case .quickScan:
            for square in marks { annotations.tints[square] = .quickScan }
            if let grade = quickScanGrade, feedback != nil {
                for square in marks { annotations.rings[square] = grade.extra.contains(square) ? .extra : .correct }
                for square in grade.missed { annotations.rings[square] = .missed }
            }
        case .done:
            if let outcome, outcome.detail.failReason == .badMove, let best = ScanFeedback.bestMove(puzzle.answer) {
                annotations.arrows = [BoardArrow(from: moveFrom(best), to: moveTo(best), side: .own)]
            }
        default: break
        }
        return annotations
    }

    // MARK: Steps

    /// Plays the opponent's last move after `REPLY_MS` and starts the quick scan. Called by the
    /// view's task, so leaving the puzzle cancels it; coming back starts the puzzle over.
    func begin() async {
        guard !begun, step == .lastMove else { return }
        begun = true
        do { try await clock.sleep(until: clock.now + .milliseconds(REPLY_MS)) }
        catch { begun = false; return }
        guard !Task.isCancelled else { begun = false; return }
        fen = startFen
        highlight = (moveFrom(puzzle.lastMove), moveTo(puzzle.lastMove))
        start(.quickScan)
    }

    /// Marks or clears a square in the quick scan, undoable through the window's `UndoManager`.
    func toggle(_ square: String) {
        guard canMark else { return }
        flip(square)
        history.append(square)
        register(square)
    }

    /// The Undo button: through `UndoManager` when it holds the mark, so it and shake to undo
    /// share one stack, else straight from `history`.
    func undo() {
        guard canUndo else { return }
        if let undoManager, undoManager.canUndo { undoManager.undo() }
        else if let square = history.popLast() { flip(square) }
    }

    /// Flag or No Flag: grades the quick scan and the call, and shows feedback.
    func call(_ flag: Bool) {
        guard canMark else { return }
        let ms = elapsedMs()
        let grade = ScanGrader.gradeQuickScan(tapped: marks, answer: puzzle.answer)
        steps.quickScan = ScanMarkStep(ms: ms, limitMs: ScanTiming.limitMs(.quickScan), missed: grade.missed, extra: grade.extra)
        quickScanGrade = grade
        flagCall = flag
        endStep()
        feedback = .quickScan(grade, flag: ScanGrader.gradeFlag(called: flag, answer: puzzle.answer),
                              answer: puzzle.answer, startFen: startFen, ms: ms)
    }

    /// Continue after the quick scan's feedback. v1 goes to the move whatever the call; the
    /// Flag branch's targets and arrows come with S07.
    func proceed() {
        guard step == .quickScan, feedback != nil else { return }
        marks = []
        start(.move)
    }

    /// The solver's move: graded against the maker's scores, then the puzzle's result.
    func play(_ move: Uci) {
        guard canMove, let flagCall, Board.isLegal(fen, move), let next = Board.applyUci(fen, move) else { return }
        let ms = elapsedMs()
        let grade = ScanGrader.gradeMove(move, answer: puzzle.answer)
        steps.move = ScanMoveStep(ms: ms, limitMs: ScanTiming.limitMs(.move(flagCall: flagCall)), played: move, lossCp: grade.lossCp)
        let outcome = ScanGrader.result(of: steps, flagCall: flagCall, answer: puzzle.answer)
        fen = next
        highlight = (moveFrom(move), moveTo(move))
        endStep()
        self.outcome = outcome
        step = .done
        feedback = .move(move, grade: grade, outcome: outcome, answer: puzzle.answer,
                         startFen: startFen, flagCall: flagCall, ms: ms)
    }

    /// The attempt to record once the result is shown.
    func attempt(runId: String, playedAt: Int64) -> ScanAttempt? {
        guard let outcome, let flagCall else { return nil }
        return ScanAttempt(puzzleId: puzzle.id, runId: runId, flagCall: flagCall, outcome: outcome, playedAt: playedAt)
    }

    /// The window's undo manager, so shake to undo and the three-finger swipe reach the marks.
    func attach(_ manager: UndoManager?) {
        guard manager !== undoManager else { return }
        undoManager?.removeAllActions(withTarget: self)
        undoManager = manager
    }

    /// Leaving the puzzle: nothing of it is kept (plan §2.2).
    func cancel() { undoManager?.removeAllActions(withTarget: self) }

    // MARK: Private

    private func start(_ next: ScanStep) {
        step = next; feedback = nil; history = []
        startedAt = clock.now; stepStarted = now()
    }

    /// Undo never leaves a step, so its actions go when it ends.
    private func endStep() {
        stepStarted = nil; history = []
        undoManager?.removeAllActions(withTarget: self)
    }

    private func elapsedMs() -> Int {
        let elapsed = clock.now - startedAt
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func flip(_ square: String) {
        if marks.contains(square) { marks.remove(square) } else { marks.insert(square) }
    }

    private func register(_ square: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in model.revert(square) }
        undoManager.setActionName("Mark")
    }

    /// An undone mark; registers its redo.
    private func revert(_ square: String) {
        guard canMark, history.last == square else { return }
        history.removeLast()
        flip(square)
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in model.toggle(square) }
        undoManager.setActionName("Mark")
    }
}
