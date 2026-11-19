import Foundation

// The Scan tab's views of the library, over the shared derive code: status,
// review, progress and resume follow exactly the Puzzles tab's rules.

/// The pool in the order puzzles arrived, then id.
func scanPool(_ library: Library) -> [ScanPuzzle] {
    library.scanPuzzles.sorted { $0.addedAt == $1.addedAt ? $0.id < $1.id : $0.addedAt < $1.addedAt }
}

func scanRecords(_ library: Library) -> [String: PuzzleRecord] { puzzleRecords(library.scanAttempts) }

/// The Solved / To review / New card for the whole pool.
func scanStats(_ library: Library) -> Stats {
    statsFor(scanPool(library).map(\.id), scanRecords(library))
}

/// Puzzles whose latest result is a fail, or a pass with target or arrow misses, in pool order.
func scanReviewIds(_ library: Library) -> [String] {
    reviewIds(scanPool(library).map(\.id), scanRecords(library))
}

/// A new run's queue: the whole pool at random with recently seen puzzles at
/// the back, or the puzzles to review, shuffled.
func scanQueue(_ library: Library, _ mode: SessionMode,
               _ rand: () -> Double = { Double.random(in: 0..<1) }) -> [String] {
    switch mode {
    case .reviewMistakes: makeQueue(.reviewMistakes, scanReviewIds(library), rand)
    default: orderForGlobalDraw(scanPool(library).map(\.id), recentIds(library.scanAttempts), rand)
    }
}

/// `SCOPE_ALL` or `SCOPE_REVIEW`.
func scanRunIn(_ library: Library, _ scope: RunScope) -> Run? {
    library.scanRuns.first { $0.scope == scope }
}

func scanProgressOf(_ library: Library, _ run: Run) -> RunProgress {
    runProgress(run, library.scanAttempts, Set(library.scanPuzzles.map(\.id)))
}

/// The scan session's counter and bar: every finished puzzle moves them, retries add to the total.
func scanPositionOf(_ library: Library, _ run: Run) -> RunPosition {
    runPosition(run, library.scanAttempts, Set(library.scanPuzzles.map(\.id)))
}

/// A scope has a scan run with something still to serve.
func scanResumable(_ library: Library, _ scope: RunScope) -> Bool {
    guard let run = scanRunIn(library, scope) else { return false }
    return scanProgressOf(library, run).current.map { !$0.isEmpty } ?? false
}
