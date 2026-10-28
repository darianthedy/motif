import Foundation
import Observation

/// Time for the analyzer's debounce and throttle, injected so tests can step it.
protocol AnalysisClock: Sendable {
    /// Time elapsed since some fixed start.
    var now: Duration { get }
    /// Returns once `now` reaches `deadline`. Timers take their deadline when they're
    /// set, so a timer set just before the clock moves still counts from then.
    func sleep(until deadline: Duration) async throws
}

struct SystemClock: AnalysisClock {
    private let start = ContinuousClock.now
    var now: Duration { ContinuousClock.now - start }
    func sleep(until deadline: Duration) async throws { try await Task.sleep(until: start + deadline, clock: .continuous) }
}

/// Least-recently-used results by FEN.
struct EvaluationCache<Value> {
    let capacity: Int
    private var entries: [String: Value] = [:]
    /// Least recently used first.
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func value(for fen: String) -> Value? {
        guard let value = entries[fen] else { return nil }
        touch(fen)
        return value
    }

    mutating func store(_ value: Value, for fen: String) {
        if entries.updateValue(value, forKey: fen) == nil, entries.count > capacity {
            entries[order.removeFirst()] = nil
        }
        touch(fen)
    }

    private mutating func touch(_ fen: String) {
        order.removeAll { $0 == fen }
        order.append(fen)
    }
}

/// The ranked lines found for one position, by rank, and how many the search asked for.
struct LineSet {
    let count: Int
    var lines: [Int: EngineLine] = [:]
}

/// Follows the position on the game screen with live Stockfish evaluations.
///
/// Stepping to a new position stops the running search at once; the next search
/// starts once `show` has been quiet for `debounce`, and only after the stopped
/// search's `bestmove` says the engine is idle. Each search is a job with an id, and
/// output is applied only while its job is the one searching, so lines that arrive
/// between `stop` and `bestmove` are dropped.
@MainActor @Observable final class Analyzer {
    nonisolated static let debounce = Duration.milliseconds(250)
    /// Minimum time between published partial results (about 10 a second).
    nonisolated static let throttle = Duration.milliseconds(100)
    nonisolated static let targetDepth = 22
    nonisolated static let moveTime = Duration.seconds(20)
    nonisolated static let cacheSize = 256

    /// The latest result for the position being shown, or nil before the first one.
    private(set) var evaluation: Evaluation?
    /// The best lines for the position being shown, best first; at most `lineCount`.
    private(set) var lines: [EngineLine] = []

    /// How many lines the engine searches (UCI MultiPV). More lines make each one
    /// slower, so the screen asks for 3 only while it shows them.
    var lineCount = 1 {
        didSet {
            guard lineCount != oldValue else { return }
            let shown = fen
            halt()
            if let shown { show(fen: shown) }
        }
    }

    /// Off while neither the bar nor the engine lines are shown: stops the search and starts no new ones.
    var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            if enabled, let fen { show(fen: fen) } else if !enabled { halt() }
        }
    }

    private enum EngineState: Equatable { case idle, searching(job: Int), stopping }

    private struct Job {
        let id: Int
        let fen: String
        let side: Side
        /// The debounce has passed, so it starts as soon as the engine is idle.
        var due = false
        var started = false
        /// The MultiPV the search ran with.
        var count = 1
    }

    @ObservationIgnored private let engine: any UCIEngine
    @ObservationIgnored private let clock: any AnalysisClock
    @ObservationIgnored private var cache = EvaluationCache<Evaluation>(capacity: Analyzer.cacheSize)
    @ObservationIgnored private var lineCache = EvaluationCache<LineSet>(capacity: Analyzer.cacheSize)
    /// The MultiPV last sent to the engine; it starts at Stockfish's default.
    @ObservationIgnored private var sentCount = 1
    /// The position on screen, kept while paused so `resume` can pick it up again.
    @ObservationIgnored private var fen: String?
    @ObservationIgnored private var job: Job?
    @ObservationIgnored private var jobs = 0
    @ObservationIgnored private var state = EngineState.idle
    /// Bumped by every `show`, so only the last debounce timer fires.
    @ObservationIgnored private var timer = 0
    @ObservationIgnored private var active = true
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var publishedAt: Duration?
    @ObservationIgnored private var unpublished: Evaluation?
    @ObservationIgnored private var linesChanged = false
    @ObservationIgnored private var trailing: Int?

    init(engine: any UCIEngine, clock: any AnalysisClock = SystemClock()) {
        self.engine = engine
        self.clock = clock
    }

    /// The app's analyzer: Stockfish, or a `FakeEngine` in the in-memory debug
    /// configuration the UI tests run, so they don't compete with a real search. It's
    /// silent except on the `game-eval` route, where it plays `FakeEngine.climb`.
    static func live(route: String? = nil) -> Analyzer {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "MotifMemoryBackend") {
            return Analyzer(engine: route == "game-eval" ? FakeEngine.climb() : FakeEngine())
        }
        #endif
        return Analyzer(engine: StockfishEngine.shared)
    }

    /// Call whenever the screen's position changes.
    func show(fen: String) {
        self.fen = fen
        guard enabled, active, job?.fen != fen else { return }
        if let done = Self.terminal(fen) {
            halt()
            evaluation = done
            lines = []
            return
        }
        if let done = complete(fen) {
            halt()
            evaluation = done
            lines = shownLines(fen)
            return
        }
        evaluation = cache.value(for: fen)
        lines = shownLines(fen)
        stopSearch()
        jobs += 1
        job = Job(id: jobs, fen: fen, side: UCI.sideToMove(fen))
        publishedAt = nil; unpublished = nil; linesChanged = false; trailing = nil
        timer += 1
        let generation = timer, deadline = clock.now + Self.debounce
        Task { [weak self, clock] in
            try? await clock.sleep(until: deadline)
            self?.fire(generation)
        }
    }

    /// The screen went away or the app left `.active`: stop searching.
    func pause() {
        active = false
        halt()
    }

    /// Back on screen and active: analyse the current position again.
    func resume() {
        active = true
        if let fen { show(fen: fen) }
    }

    // MARK: Jobs

    private func complete(_ fen: String) -> Evaluation? {
        guard let cached = cache.value(for: fen), cached.final || cached.depth >= Self.targetDepth else { return nil }
        guard lineCount == 1 || (lineCache.value(for: fen)?.count ?? 1) >= lineCount else { return nil }
        return cached
    }

    private func fire(_ generation: Int) {
        guard generation == timer, job?.started == false else { return }
        job?.due = true
        startIfIdle()
    }

    private func startIfIdle() {
        guard state == .idle, enabled, active, let next = job, next.due, !next.started else { return }
        readIfNeeded()
        job?.started = true
        job?.count = lineCount
        if sentCount != lineCount {
            engine.send("setoption name MultiPV value \(lineCount)")
            sentCount = lineCount
        }
        state = .searching(job: next.id)
        engine.send("position fen \(next.fen)")
        engine.send("go depth \(Self.targetDepth) movetime \(Int(Self.moveTime / .milliseconds(1)))")
    }

    private func stopSearch() {
        guard case .searching = state else { return }
        engine.send("stop")
        state = .stopping
    }

    /// Stops any search and forgets the job, so the next `show` starts afresh.
    private func halt() {
        stopSearch()
        job = nil
        timer += 1
        unpublished = nil; linesChanged = false; trailing = nil
    }

    /// The cached lines for `fen`, best first, cut to `lineCount`.
    private func shownLines(_ fen: String) -> [EngineLine] {
        guard let set = lineCache.value(for: fen) else { return [] }
        return set.lines.keys.sorted().prefix(lineCount).compactMap { set.lines[$0] }
    }

    // MARK: Engine output

    private func readIfNeeded() {
        guard reader == nil else { return }
        let lines = engine.lines
        // Parsing stays off the main actor; only parsed lines hop to it.
        reader = Task.detached(priority: .userInitiated) { [weak self] in
            for await text in lines {
                guard let line = UCI.parse(text) else { continue }
                guard let self else { return }
                await self.receive(line)
            }
        }
    }

    private func receive(_ line: UCI.Line) {
        switch line {
        case .bestmove:
            if case .searching(let id) = state, let job, job.id == id { finish(job) }
            state = .idle
            startIfIdle()
        case let .info(depth, score, pv, rank):
            guard case .searching(let id) = state, let job, job.id == id else { return }
            let white = UCI.whiteView(score, job.side)
            if !pv.isEmpty {
                var set = lineCache.value(for: job.fen).flatMap { $0.count == job.count ? $0 : nil } ?? LineSet(count: job.count)
                set.lines[rank] = EngineLine(depth: depth, score: white, moves: pv)
                lineCache.store(set, for: job.fen)
                linesChanged = true
            }
            if rank == 1 {
                let result = Evaluation(fen: job.fen, depth: depth, score: white, final: false)
                cache.store(result, for: job.fen)
                unpublished = result
            }
            publish(job.id)
        }
    }

    /// Publishes the newest partial result now, or at the end of the throttle window.
    private func publish(_ id: Int) {
        let now = clock.now
        guard let publishedAt, now - publishedAt < Self.throttle else { return flush(id) }
        guard trailing != id else { return }
        trailing = id
        let deadline = publishedAt + Self.throttle
        Task { [weak self, clock] in
            try? await clock.sleep(until: deadline)
            self?.flush(id)
        }
    }

    private func flush(_ id: Int) {
        if trailing == id { trailing = nil }
        guard let job, job.id == id, state == .searching(job: id), unpublished != nil || linesChanged else { return }
        if let unpublished { evaluation = unpublished }
        if linesChanged { lines = shownLines(job.fen) }
        unpublished = nil; linesChanged = false
        publishedAt = clock.now
    }

    /// The search ended on its own: its last result is final.
    private func finish(_ job: Job) {
        unpublished = nil; linesChanged = false; trailing = nil
        lines = shownLines(job.fen)
        guard let last = cache.value(for: job.fen) else { return }
        let done = Evaluation(fen: last.fen, depth: last.depth, score: last.score, final: true)
        cache.store(done, for: done.fen)
        evaluation = done
    }

    // MARK: Positions the engine isn't needed for

    /// Checkmate is a mate in 0 for the side not to move; stalemate and insufficient
    /// material are dead level.
    nonisolated static func terminal(_ fen: String) -> Evaluation? {
        guard Board.turnOf(fen) != nil else { return nil }
        if Board.isCheckmate(fen) { return Evaluation(fen: fen, depth: 0, score: .mate(0), final: true) }
        if Board.targetsFrom(fen, "").isEmpty || insufficientMaterial(fen) {
            return Evaluation(fen: fen, depth: 0, score: .cp(0), final: true)
        }
        return nil
    }

    /// chess.js's rule: bare kings, a single minor piece, or only bishops all on one colour.
    private nonisolated static func insufficientMaterial(_ fen: String) -> Bool {
        var types: [PieceType] = [], bishopSquares = Set<Bool>()
        for (index, piece) in Board.snapshot(fen).cells.enumerated() {
            guard let piece, piece.type != .king else { continue }
            types.append(piece.type)
            if piece.type == .bishop { bishopSquares.insert((index / 8 + index % 8) % 2 == 1) }
        }
        if types.isEmpty { return true }
        if types == [.knight] || types == [.bishop] { return true }
        return types.allSatisfy { $0 == .bishop } && bishopSquares.count == 1
    }
}
