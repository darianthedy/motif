enum SessionMode: String, Codable, CaseIterable, Sendable {
    case ordered, randomInCollection, randomGlobal, reviewMistakes
}

/// Put other puzzles between a miss and its retry, so the answer is not echoed.
let RETRY_GAP = 3
/// Bound the backlog in a bad run.
let MAX_RETRIES = 10
/// Recently seen puzzles go to the back of a global draw.
let RECENT_MEMORY = 24

func shuffle<T>(_ items: [T], _ rand: () -> Double) -> [T] {
    var out = items
    guard out.count > 1 else { return out }
    for i in stride(from: out.count - 1, through: 1, by: -1) {
        let j = Int((rand() * Double(i + 1)).rounded(.down))
        out.swapAt(i, j)
    }
    return out
}

/// Global draws arrive already biased and shuffled; shuffling again undoes it.
func makeQueue(_ mode: SessionMode, _ orderedIds: [String],
               _ rand: () -> Double = { Double.random(in: 0..<1) }) -> [String] {
    mode == .ordered || mode == .randomGlobal ? orderedIds : shuffle(orderedIds, rand)
}

/// Recent puzzles move to the back rather than disappearing. Small libraries
/// must still return something even when everything was recently seen.
func orderForGlobalDraw(_ allIds: [String], _ recentIds: [String],
                        _ rand: () -> Double = { Double.random(in: 0..<1) }) -> [String] {
    let recent = Set(recentIds.prefix(RECENT_MEMORY))
    let fresh = shuffle(allIds.filter { !recent.contains($0) }, rand)
    let stale = shuffle(allIds.filter { recent.contains($0) }, rand)
    return fresh + stale
}
