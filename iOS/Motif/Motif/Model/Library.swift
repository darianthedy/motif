/// Collections in creation order, then id.
func collectionsOf(_ library: Library) -> [Collection] {
    library.collections.sorted {
        $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
    }
}

func puzzlesIn(_ library: Library, _ collectionId: String) -> [Puzzle] {
    library.puzzles.filter { $0.collectionId == collectionId }.sorted {
        $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position
    }
}

func allPuzzles(_ library: Library) -> [Puzzle] {
    collectionsOf(library).flatMap { puzzlesIn(library, $0.id) }
}

func runIn(_ library: Library, _ scope: RunScope) -> Run? {
    library.runs.first { $0.scope == scope }
}

func progressOf(_ library: Library, _ run: Run) -> RunProgress {
    runProgress(run, library.attempts, Set(library.puzzles.map(\.id)))
}

/// A scope has a run with something still to serve.
func resumable(_ library: Library, _ scope: RunScope) -> Bool {
    guard let run = runIn(library, scope) else { return false }
    return progressOf(library, run).current.map { !$0.isEmpty } ?? false
}

struct ImportPlan: Equatable, Sendable {
    var puzzles: [NewPuzzle]
    var added: Int
}

/// Existing content keeps its place. New content appends in file order.
/// Within-file dedupe belongs to the importer, not this planning operation.
func planImport(_ existing: [Puzzle], _ incoming: [PuzzleContent], _ collectionId: String) -> ImportPlan {
    var positions: [String: Int] = [:]
    for puzzle in existing { positions[contentKey(puzzle)] = puzzle.position }
    var next = existing.reduce(0) { max($0, $1.position + 1) }
    var added = 0
    let puzzles = incoming.map { content in
        let position: Int
        if let existing = positions[contentKey(content)] {
            position = existing
        } else {
            position = next
            next += 1
            added += 1
        }
        return NewPuzzle(content, collectionId: collectionId, position: position)
    }
    return ImportPlan(puzzles: puzzles, added: added)
}
