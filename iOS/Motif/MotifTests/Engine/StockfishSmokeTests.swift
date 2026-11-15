import XCTest
@testable import Motif

/// The real engine in the simulator: both nets are bundled, Stockfish loads them and
/// a short search streams scores and ends in a best move.
final class StockfishSmokeTests: XCTestCase {
    /// The app's own engine: started once per process and never stopped (a stopped or
    /// deinitialized ChessKitEngine closes the pipe it moved stdout onto). Each run
    /// subscribes to its lines afresh, so a retry or a repeat (`-test-iterations`)
    /// talks to the same running Stockfish. Starting a second ChessKitEngine, or
    /// calling `start()` again, hands out a response stream that ended with the last
    /// run's reader, and the run then waits out the deadline for a `readyok`.
    private var engine: StockfishEngine { .shared }

    /// A depth-8 search from the start position takes well under a second, even on
    /// a 3-core runner; the budgets below are only there so the test always ends.
    private static let depth = 8
    /// How long one search may run before the test sends `stop`, which makes
    /// Stockfish print its best move at once.
    private static let searchBudget = Duration.seconds(15)
    /// How long after `stop` the test waits before searching again.
    private static let stopBudget = Duration.seconds(5)
    private static let searches = 3
    /// Covers loading the 133 MB net and every search.
    private static let deadline = Duration.seconds(120)

    private enum Event: Sendable {
        case line(String)
        case tick
    }

    /// What one `go` produced, for the failure message and the attachment.
    private struct Search: CustomStringConvertible {
        var infos = 0
        var scored = 0
        var stopped = false
        var bestmove: String?
        var started: ContinuousClock.Instant
        var description: String {
            "\(infos) info lines, \(scored) scored" + (stopped ? ", stopped" : "") + (bestmove.map { ", bestmove \($0)" } ?? "")
        }
    }

    func testBothNetsAreBundled() {
        let names = Stockfish.nets.map(\.lastPathComponent)
        XCTAssertEqual(names.count, 2, "expected the big and the small net, found \(names)")
        for url in Stockfish.nets {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            XCTAssertGreaterThan(size, 1_000_000, "\(url.lastPathComponent) looks truncated")
        }
    }

    /// ChessKitEngine reads Stockfish's stdout in chunks on the main run loop, splits
    /// each chunk on newlines without carrying a cut line into the next one, and yields
    /// every line from its own `Task`, so a line can arrive out of order, cut in two
    /// or not at all. The CI failures (2026-11-11) had `go` reach Stockfish (it printed
    /// the go-time info strings) and then no `bestmove` for 40 s. So a search that
    /// overruns is stopped, which forces a `bestmove`, and if that never comes either
    /// the search is run again. Stockfish reports each net it evaluates with ("NNUE
    /// evaluation using …") on every `go`, and a cut line loses that report (2026-11-15:
    /// "NNUE evaluation using" alone), so a search that ends without both reports is run
    /// again too. Each search's line counts go in the failure message, to tell a
    /// stalled search (no info lines) from dropped output (info lines, no bestmove).
    func testSearchesStartPositionWithBundledNets() async throws {
        let engine = self.engine
        let nets = Stockfish.nets.map(\.lastPathComponent)
        let lines = engine.lines

        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        let pump = Task {
            for await line in lines { sink.yield(.line(line)) }
        }
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                sink.yield(.tick)
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now + Self.deadline
        var ready = false
        var strings: [String] = []
        var searches: [Search] = []
        var reported: Set<String> = []

        func search() {
            searches.append(Search(started: clock.now))
            engine.send("position startpos")
            engine.send("go depth \(Self.depth)")
        }

        // StockfishEngine holds commands until ChessKitEngine's setup (the nets among
        // it) is done; this readyok comes once Stockfish has handled all of it, and
        // after any output a previous run left behind.
        engine.send("isready")

        loop: for await event in events {
            switch event {
            case .line("readyok"):
                guard !ready else { break }
                ready = true
                search()
            case .line(let line) where line.hasPrefix("info "):
                if line.hasPrefix("info string ") {
                    let string = String(line.dropFirst("info string ".count))
                    strings.append(string)
                    if string.contains("NNUE evaluation using") {
                        reported.formUnion(nets.filter { string.contains($0) })
                    }
                }
                guard ready, !searches.isEmpty else { break }
                searches[searches.count - 1].infos += 1
                if line.hasPrefix("info depth "), line.contains(" score ") { searches[searches.count - 1].scored += 1 }
            case .line(let line) where line.hasPrefix("bestmove "):
                // A bestmove before our readyok is a previous run's.
                guard ready, !searches.isEmpty, searches[searches.count - 1].bestmove == nil else { break }
                searches[searches.count - 1].bestmove = String(line.split(separator: " ")[1])
                if reported.count == nets.count || searches.count >= Self.searches { break loop }
                search()
            case .line:
                break
            case .tick:
                let now = clock.now
                if now >= deadline { break loop }
                guard let current = searches.last, current.bestmove == nil else { break }
                if !current.stopped, now - current.started > Self.searchBudget {
                    searches[searches.count - 1].stopped = true
                    engine.send("stop")
                } else if current.stopped, now - current.started > Self.searchBudget + Self.stopBudget,
                          searches.count < Self.searches {
                    search()
                }
            }
        }
        pump.cancel()
        ticker.cancel()
        sink.finish()
        if searches.last.map({ $0.bestmove == nil }) ?? false { engine.send("stop") }

        let report = "searches: \(searches); info strings: \(strings)"
        await MainActor.run {
            XCTContext.runActivity(named: "Stockfish transcript") { activity in
                let attachment = XCTAttachment(string: report)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }

        XCTAssertTrue(ready, "the handshake didn't finish; \(report)")
        let move = try XCTUnwrap(searches.compactMap(\.bestmove).last, "no bestmove; \(report)")
        XCTAssertFalse(move.isEmpty || move == "(none)", report)
        XCTAssertGreaterThan(searches.map(\.scored).reduce(0, +), 0, "no info line carried a score; \(report)")
        for net in nets {
            XCTAssertTrue(reported.contains(net), "Stockfish didn't report evaluating with \(net); \(report)")
        }
    }
}
