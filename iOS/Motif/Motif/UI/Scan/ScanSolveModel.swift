import Foundation
import Observation

/// One scan puzzle, step by step (Scan plan §5): the board, the marks, the step's time and the
/// attempt being built. Grading is `ScanGrader`'s; this model only collects input and times it.
/// The last move plays, the quick scan ends with Flag or No Flag, feedback; on a flagged puzzle
/// with a full scan the targets, feedback, the arrows, feedback (after a wrong No Flag too: the
/// puzzle has failed, but the scan it skipped is still drilled); then the move, held ghosted for
/// the final check after a full scan, and its feedback. Each step's marks stay on the board,
/// dimmed, through the steps after it. Nothing is saved until the view records `outcome`.
/// A step with a hard limit (`ScanLimits`) ends as it stands when the limit runs out: missing
/// marks are soft misses, and a quick scan with no call or no move in time fails the puzzle.
@Observable @MainActor final class ScanSolveModel {
    let puzzle: ScanPuzzle
    /// The side to move after the opponent's last move.
    let solver: Side
    private(set) var step = ScanStep.lastMove
    private(set) var fen: String
    private(set) var highlight: (from: String, to: String)?
    /// What the step on screen has marked: squares, targets or arrows.
    private(set) var current = ScanMarks()
    /// What the earlier marking steps left, shown dimmed and read-only under the step's own.
    private(set) var carried = ScanMarks()
    private(set) var flagCall: Bool?
    /// The graded step's feedback; nil while a step is being played.
    private(set) var feedback: ScanFeedback?
    /// When the running step started, for the elapsed-time display; nil between steps.
    private(set) var stepStarted: Date?
    /// When the running step's hard limit runs out, for the countdown; nil while record-only.
    private(set) var deadline: Date?
    /// The hard limits in force for this puzzle, fixed when it starts.
    let limits: ScanLimits
    /// The move under final check: shown ghosted until Play It or Take Back.
    private(set) var candidate: Uci?
    /// Set once the move is graded: what the view records.
    private(set) var outcome: ScanOutcome?
    /// The step's marks before each change, newest last: what Undo goes back to.
    private(set) var history: [ScanMarks] = []
    @ObservationIgnored private(set) var quickScanGrade: ScanMarkGrade?
    @ObservationIgnored private(set) var targetsGrade: ScanMarkGrade?
    @ObservationIgnored private(set) var arrowsGrade: ScanMarkGrade?
    @ObservationIgnored private var steps = ScanSteps()
    @ObservationIgnored private let clock: any AnalysisClock
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var startedAt = Duration.zero
    @ObservationIgnored private var begun = false
    @ObservationIgnored private weak var undoManager: UndoManager?
    /// Kept so the move's result can say how much it gave away.
    @ObservationIgnored private let startFen: String
    /// Moves taken back at the final check, recorded with the move.
    @ObservationIgnored private var takeBacks = 0
    /// Sleeps until the running step's limit, then ends it; cancelled when the step ends first.
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    /// Moves on from a step found cleanly and in time, after `autoAdvanceMs`.
    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    /// Off with VoiceOver or Switch Control, so the feedback is never cut short.
    var autoAdvance = true
    /// How long a clean step's feedback stays before the next step starts; 0 never moves on.
    let autoAdvanceMs: Int
    static let defaultAutoAdvanceMs = 900
    /// `-MotifScanAutoAdvanceMs <ms>` on launch overrides the pause (UI tests: longer, so each
    /// feedback can be read, or 0 for screenshots of it).
    static var configuredAutoAdvanceMs: Int {
        UserDefaults.standard.object(forKey: "MotifScanAutoAdvanceMs") == nil
            ? defaultAutoAdvanceMs : UserDefaults.standard.integer(forKey: "MotifScanAutoAdvanceMs")
    }

    init(_ puzzle: ScanPuzzle, limits: ScanLimits = ScanLimits(), clock: any AnalysisClock = SystemClock(),
         now: @escaping () -> Date = Date.init, autoAdvanceMs: Int = ScanSolveModel.defaultAutoAdvanceMs) {
        self.puzzle = puzzle; self.limits = limits; self.clock = clock; self.now = now; self.autoAdvanceMs = autoAdvanceMs
        fen = puzzle.fenBefore
        startFen = puzzle.startFen ?? puzzle.fenBefore
        solver = Board.turnOf(startFen) ?? .white
    }

    // MARK: Reading

    /// The quick scan's marked squares.
    var marks: Set<String> { current.squares }
    /// A marking step (quick scan, targets, arrows) is open for input.
    var canMark: Bool { [.quickScan, .targets, .arrows].contains(step) && feedback == nil }
    var canMove: Bool { step == .move }
    /// A flagged puzzle with targets and arrows runs them after the quick scan, whatever the call:
    /// a wrong No Flag has already failed it, but the scan is the part most worth drilling.
    var runsFullScan: Bool { flagCall != nil && puzzle.answer.hasFullScan }
    /// A move is held for the final check only after the full scan (Puzzle flow 6); a quiet No
    /// Flag and v1 puzzles play at once.
    var needsFinalCheck: Bool { runsFullScan }
    var canUndo: Bool { canMark && !history.isEmpty }
    var boardMode: BoardMode {
        switch step {
        case .quickScan: .markSquares
        case .targets: .markTargets
        case .arrows: .drawArrows
        default: .play
        }
    }
    var boardInteractive: Bool { canMark || canMove }
    /// The opponent's last move in SAN ("Nf6").
    var lastMoveSan: String { Board.sanFor(puzzle.fenBefore, puzzle.lastMove) ?? puzzle.lastMove.text }

    /// The move under final check in SAN ("Nxe5"), for the prompt.
    var candidateSan: String? { candidate.map { Board.sanFor(startFen, $0) ?? $0.text } }

    /// The step's one line of guidance. No bare "Re5?": a "?" after a move reads as the chess
    /// annotation for a mistake (playtest 3).
    var prompt: String {
        switch step {
        case .lastMove: "Their move."
        case .quickScan: "Last move: \(lastMoveSan)"
        case .targets: "Red, orange, dots."
        case .arrows: "Both sides."
        case .move: "Your move."
        case .finalCheck: "Play \(candidateSan ?? "this move")?"
        default: ""
        }
    }

    /// Marks while a step is played; once it's graded, rings for found, missed and extra squares
    /// (a missed target shows the answer's mark) and the missed arrows in outline; after a failed
    /// move, an arrow for the best one.
    var annotations: BoardAnnotations {
        var annotations = current.annotations
        if [.targets, .arrows].contains(step) { carry(into: &annotations) }
        switch step {
        case .quickScan:
            if let grade = quickScanGrade, feedback != nil {
                for square in marks { annotations.rings[square] = grade.extra.contains(square) ? .extra : .correct }
                for square in grade.missed { annotations.rings[square] = .missed }
            }
        case .targets:
            guard let grade = targetsGrade, feedback != nil, let targets = puzzle.answer.targets else { break }
            let missed = Set(grade.missed), extra = Set(grade.extra)
            for square in current.targets.keys {
                annotations.rings[square] = missed.contains(square) ? .missed : extra.contains(square) ? .extra : .correct
            }
            for square in grade.missed where current.targets[square] == nil {
                annotations.rings[square] = .missed
                if targets.red.contains(square) { annotations.tints[square] = .red }
                else if targets.orange.contains(square) { annotations.tints[square] = .orange }
                else { annotations.dots.insert(square) }
            }
        case .arrows:
            guard let grade = arrowsGrade, feedback != nil, let answer = puzzle.answer.arrows else { break }
            let expected = Set(answer.map(\.line)), missed = Set(grade.missed)
            for index in annotations.arrows.indices where expected.contains(annotations.arrows[index].line) {
                annotations.arrows[index].style = .correct
            }
            for arrow in answer where missed.contains(arrow.line) {
                annotations.arrows.append(BoardArrow(from: arrow.from, to: arrow.to, side: arrow.side == .own ? .own : .theirs, style: .missed))
            }
        case .finalCheck:
            if let candidate, let piece = Board.pieceAt(fen, moveTo(candidate)) {
                annotations.ghost = BoardGhost(square: moveTo(candidate), piece: piece)
            }
        case .done:
            annotations.arrows = resultArrows
        default: break
        }
        return annotations
    }

    /// The result on the board: the move played, ticked when it was the best; otherwise the best
    /// move. Then the best line's reply, dashed, when the line starts with the move shown.
    var resultArrows: [BoardArrow] {
        guard step == .done else { return [] }
        let played = steps.move?.played, best = ScanFeedback.bestMove(puzzle.answer)
        var arrows: [BoardArrow] = []
        let shown: Uci
        if let played, played.text == best?.text || puzzle.answer.lossCp(played) == 0 {
            arrows.append(BoardArrow(from: moveFrom(played), to: moveTo(played), side: .own, style: .correct))
            shown = played
        } else if let best {
            arrows.append(BoardArrow(from: moveFrom(best), to: moveTo(best), side: .own))
            shown = best
        } else { return [] }
        if let line = puzzle.answer.bestLine, line.count > 1, line[0].text == shown.text {
            arrows.append(BoardArrow(from: moveFrom(line[1]), to: moveTo(line[1]), side: .theirs))
        }
        return arrows
    }

    /// The earlier steps' tints and dots, dimmed, on squares the step hasn't marked itself.
    private func carry(into annotations: inout BoardAnnotations) {
        let earlier = carried.annotations
        for (square, mark) in earlier.tints where annotations.tints[square] == nil && !annotations.dots.contains(square) {
            annotations.tints[square] = mark; annotations.faded.insert(square)
        }
        for square in earlier.dots where annotations.tints[square] == nil && !annotations.dots.contains(square) {
            annotations.dots.insert(square); annotations.faded.insert(square)
        }
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

    /// A tap on a square in the step on screen: a quick-scan mark, or the next target mark.
    func tap(_ square: String) {
        switch step {
        case .quickScan: toggle(square)
        case .targets: markTargets([square])
        default: break
        }
    }

    /// Marks or clears a square in the quick scan, undoable through the window's `UndoManager`.
    func toggle(_ square: String) {
        guard canMark, step == .quickScan else { return }
        change("Mark") { $0.toggle(square) }
    }

    /// Target marks for each square in turn, as one tap each: a drag over several is one undo.
    func markTargets(_ squares: [String]) {
        guard canMark, step == .targets, !squares.isEmpty else { return }
        change(squares.count == 1 ? "Mark" : "Marks") { marks in
            for square in squares { marks.cycleTarget(square, .init(square, fen: fen)) }
        }
    }

    /// An arrow from a piece, either side's: own when the piece is the solver's. Drawing the same
    /// arrow again takes it away.
    /// Only a move of that piece, one move deep as the answer's arrows are (an arrow no piece
    /// could play is refused, never graded).
    func drawArrow(from: String, to: String) {
        guard canMark, step == .arrows, let piece = Board.pieceAt(fen, from),
              !ScanImport.arrowSans(fen, from: from, to: to).isEmpty else { return }
        change("Arrow") { $0.drawArrow(from: from, to: to, side: piece.color == solver ? .own : .theirs) }
    }

    /// A tapped arrow, or one deleted from the list under the board.
    func removeArrow(at index: Int) {
        guard canMark, step == .arrows else { return }
        change("Arrow") { $0.removeArrow(at: index) }
    }

    /// The Undo button: through `UndoManager` when it holds the change, so it and shake to undo
    /// share one stack, else straight from `history`.
    func undo() {
        guard canUndo else { return }
        if let undoManager, undoManager.canUndo { undoManager.undo() }
        else if let before = history.popLast() { current = before }
    }

    /// No Flag says nothing changed, so it's off while any square is marked (playtest 3).
    var canCallNoFlag: Bool { marks.isEmpty }

    /// Flag or No Flag: grades the quick scan and the call, and shows feedback.
    func call(_ flag: Bool) {
        guard flag || canCallNoFlag else { return }
        endQuickScan(flag, timedOut: false)
    }

    /// Next on the targets or the arrows: grades the step and shows its feedback.
    func finishStep() { finishStep(timedOut: false) }

    /// Ends the quick scan with a call, or with none when its limit ran out: then the puzzle
    /// fails there and then, its feedback the result.
    private func endQuickScan(_ flag: Bool?, timedOut: Bool) {
        guard canMark, step == .quickScan else { return }
        let ms = elapsedMs(timedOut: timedOut)
        let grade = ScanGrader.gradeQuickScan(tapped: marks, answer: puzzle.answer)
        steps.quickScan = ScanMarkStep(ms: ms, limitMs: limits.limitMs(.quickScan), missed: grade.missed, extra: grade.extra,
                                       timedOut: timedOut ? true : nil)
        quickScanGrade = grade
        flagCall = flag
        endStep()
        guard let flag else {
            outcome = ScanGrader.result(of: steps, flagCall: false, answer: puzzle.answer)
            feedback = .noCall(grade, answer: puzzle.answer, startFen: startFen, ms: ms)
            return
        }
        feedback = .quickScan(grade, flag: ScanGrader.gradeFlag(called: flag, answer: puzzle.answer),
                              answer: puzzle.answer, startFen: startFen, ms: ms)
            .limited(limits.limitMs(.quickScan), timedOut: timedOut)
        scheduleAdvance()
    }

    private func finishStep(timedOut: Bool) {
        guard canMark else { return }
        let ms = elapsedMs(timedOut: timedOut), out: Bool? = timedOut ? true : nil
        switch step {
        case .targets:
            guard let grade = ScanGrader.gradeTargets(red: current.red, orange: current.orange, dots: current.dots,
                                                      answer: puzzle.answer) else { return }
            steps.targets = ScanMarkStep(ms: ms, limitMs: limits.limitMs(.targets), missed: grade.missed, extra: grade.extra, timedOut: out)
            targetsGrade = grade
            endStep()
            feedback = .targets(grade, marked: current.targets, answer: puzzle.answer, startFen: startFen, ms: ms)
                .limited(limits.limitMs(.targets), timedOut: timedOut)
            scheduleAdvance()
        case .arrows:
            guard let grade = ScanGrader.gradeArrows(drawn: current.lines, answer: puzzle.answer) else { return }
            steps.arrows = ScanMarkStep(ms: ms, limitMs: limits.limitMs(.arrows), missed: grade.missed, extra: grade.extra, timedOut: out)
            arrowsGrade = grade
            endStep()
            feedback = .arrows(grade, answer: puzzle.answer, startFen: startFen, ms: ms)
                .limited(limits.limitMs(.arrows), timedOut: timedOut)
            scheduleAdvance()
        default: return
        }
    }

    /// The running step's limit ran out: it ends as it stands.
    func timeUp() {
        guard feedback == nil else { return }
        switch step {
        case .quickScan: endQuickScan(nil, timedOut: true)
        case .targets, .arrows: finishStep(timedOut: true)
        case .move, .finalCheck:
            // A move held at the final check wasn't played: the board goes back to before it.
            if candidate != nil { candidate = nil; fen = startFen; highlight = (moveFrom(puzzle.lastMove), moveTo(puzzle.lastMove)) }
            grade(nil, next: fen)
        default: break
        }
    }

    /// Continue after a step's feedback. A flagged puzzle with a full scan (format v2) runs it
    /// first, whatever the call; otherwise on to the move, as in v1.
    func proceed() {
        guard feedback != nil, outcome == nil else { return }
        advanceTask?.cancel(); advanceTask = nil
        switch step {
        case .quickScan: start(runsFullScan ? .targets : .move)
        case .targets: start(.arrows)
        case .arrows: start(.move)
        default: return
        }
    }

    /// The solver's move. After a full scan it's held ghosted for the final check; otherwise it's
    /// graded at once.
    func play(_ move: Uci) {
        guard canMove, flagCall != nil, Board.isLegal(fen, move), let next = Board.applyUci(fen, move) else { return }
        guard needsFinalCheck else { return grade(move, next: next) }
        // The board shows the position after the move, the moved piece see-through; the step's
        // clock keeps running, as the final check is part of the move's time.
        candidate = move
        fen = next
        highlight = (moveFrom(move), moveTo(move))
        step = .finalCheck
    }

    /// Play It on the final check: the held move is graded.
    func confirm() {
        guard step == .finalCheck, let candidate else { return }
        self.candidate = nil
        grade(candidate, next: fen)
    }

    /// Take Back on the final check: back to the move, the clock still running.
    func takeBack() {
        guard step == .finalCheck, candidate != nil else { return }
        candidate = nil
        takeBacks += 1
        fen = startFen
        highlight = (moveFrom(puzzle.lastMove), moveTo(puzzle.lastMove))
        step = .move
    }

    /// Grades the move against the maker's scores, then the puzzle's result. No move: the limit
    /// ran out first.
    private func grade(_ move: Uci?, next: String) {
        guard let flagCall else { return }
        let ms = elapsedMs(timedOut: move == nil), timed = moveStep
        let grade = move.map { ScanGrader.gradeMove($0, answer: puzzle.answer) }
        steps.move = ScanMoveStep(ms: ms, limitMs: limits.limitMs(timed), played: move, lossCp: grade?.lossCp,
                                  takeBacks: takeBacks > 0 ? takeBacks : nil)
        let outcome = ScanGrader.result(of: steps, flagCall: flagCall, answer: puzzle.answer)
        fen = next
        if let move { highlight = (moveFrom(move), moveTo(move)) }
        endStep()
        self.outcome = outcome
        step = .done
        if let move, let grade {
            feedback = ScanFeedback.move(move, grade: grade, outcome: outcome, answer: puzzle.answer,
                                         startFen: startFen, step: timed, ms: ms)
                .limited(limits.limitMs(timed), timedOut: false)
        } else {
            feedback = .noMove(outcome: outcome, answer: puzzle.answer, startFen: startFen, step: timed, ms: ms)
        }
    }

    /// The attempt to record once the result is shown.
    func attempt(runId: String, playedAt: Int64) -> ScanAttempt? {
        guard let outcome else { return nil }
        return ScanAttempt(puzzleId: puzzle.id, runId: runId, flagCall: flagCall, outcome: outcome, playedAt: playedAt)
    }

    /// The window's undo manager, so shake to undo and the three-finger swipe reach the marks.
    func attach(_ manager: UndoManager?) {
        guard manager !== undoManager else { return }
        undoManager?.removeAllActions(withTarget: self)
        undoManager = manager
    }

    /// Leaving the puzzle: nothing of it is kept (plan §2.2).
    func cancel() {
        limitTask?.cancel(); limitTask = nil
        advanceTask?.cancel(); advanceTask = nil
        undoManager?.removeAllActions(withTarget: self)
    }

    // MARK: Private

    private func start(_ next: ScanStep) {
        // The finished step's marks carry on, dimmed: the targets build on the quick scan and
        // the arrows aim at the targets. Arrows end the marking, so none are carried.
        // The targets carry as the answer has them, not as marked: the arrows aim at the true
        // targets, so a wrong colour or a missed one isn't left on the board (playtest 3).
        carried.squares.formUnion(current.squares)
        if step == .targets, let targets = puzzle.answer.targets {
            carried.targets = Self.marks(targets)
        } else {
            carried.targets.merge(current.targets) { _, new in new }
        }
        step = next; feedback = nil; history = []; current = ScanMarks()
        startedAt = clock.now; stepStarted = now()
        deadline = nil
        guard let timed = timedStep(next), let limit = limits.limitMs(timed), let started = stepStarted else { return }
        deadline = started.addingTimeInterval(Double(limit) / 1000)
        let until = startedAt + .milliseconds(limit), clock = clock
        // The move's limit runs on through the final check and any take-backs, as its clock does.
        limitTask = Task { [weak self] in
            do { try await clock.sleep(until: until) } catch { return }
            guard !Task.isCancelled else { return }
            self?.timeUp()
        }
    }

    /// The answer's targets as target marks: red, orange, and a dot on each fork square.
    private static func marks(_ targets: ScanTargets) -> [String: ScanTargetMark] {
        var marks: [String: ScanTargetMark] = [:]
        for square in targets.fork { marks[square] = .dot }
        for square in targets.orange { marks[square] = .orange }
        for square in targets.red { marks[square] = .red }
        return marks
    }

    /// The timed step a step is played under; nil for the last move and the result.
    private func timedStep(_ step: ScanStep) -> ScanTimedStep? {
        switch step {
        case .quickScan: .quickScan
        case .targets: .targets
        case .arrows: .arrows
        case .move, .finalCheck: flagCall == nil ? nil : moveStep
        default: nil
        }
    }

    /// The move's target: the flagged one after a full scan, which a wrong No Flag runs too.
    private var moveStep: ScanTimedStep { ScanTimedStep.move(flagCall: flagCall == true, steps: steps) }

    /// A step found cleanly and in time moves on by itself after a short pause; a miss waits for
    /// Continue, so it can be read. The quick scan only when its call was right too.
    private func scheduleAdvance() {
        guard autoAdvance, autoAdvanceMs > 0, feedback?.verdict == .pass, outcome == nil else { return }
        let step = step, clock = clock, until = clock.now + .milliseconds(autoAdvanceMs)
        advanceTask = Task { [weak self] in
            do { try await clock.sleep(until: until) } catch { return }
            guard !Task.isCancelled, let self, self.step == step, self.feedback != nil else { return }
            self.proceed()
        }
    }

    /// Undo never leaves a step, so its actions go when it ends; nor does the limit.
    private func endStep() {
        stepStarted = nil; deadline = nil; history = []
        limitTask?.cancel(); limitTask = nil
        undoManager?.removeAllActions(withTarget: self)
    }

    /// The step's time. When the limit cut it off, the limit itself: the task wakes a little late.
    private func elapsedMs(timedOut: Bool = false) -> Int {
        if timedOut, let timed = timedStep(step), let limit = limits.limitMs(timed) { return limit }
        let elapsed = clock.now - startedAt
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    /// One undoable change to the step's marks; nothing is registered when nothing changed.
    private func change(_ name: String, _ edit: (inout ScanMarks) -> Void) {
        var next = current
        edit(&next)
        guard next != current else { return }
        apply(next, name: name)
    }

    private func apply(_ next: ScanMarks, name: String) {
        let before = current
        history.append(before)
        current = next
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in model.revert(to: before, from: next, name: name) }
        undoManager.setActionName(name)
    }

    /// An undone change; registers its redo. Only while the step it was made in is still open.
    private func revert(to before: ScanMarks, from after: ScanMarks, name: String) {
        guard canMark, current == after, history.last == before else { return }
        history.removeLast()
        current = before
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            guard model.canMark, model.current == before else { return }
            model.apply(after, name: name)
        }
        undoManager.setActionName(name)
    }
}
