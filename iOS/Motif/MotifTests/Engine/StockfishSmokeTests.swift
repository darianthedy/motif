import ChessKitEngine
import XCTest
@testable import Motif

/// The real engine in the simulator: both nets are bundled, Stockfish loads them and
/// a short search streams scores and ends in a best move.
final class StockfishSmokeTests: XCTestCase {
    /// Never released: a stopped or deinitialized ChessKitEngine closes the pipe it
    /// moved stdout onto, and the next write to stdout would raise SIGPIPE.
    private static let engine = Stockfish.makeEngine()

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
        case response(EngineResponse)
        case tick
    }

    /// What one `go` produced, for the failure message and the attachment.
    private struct Search: CustomStringConvertible {
        var infos = 0
        var scored = 0
        var stopped = false
        var started: ContinuousClock.Instant
        var description: String {
            "\(infos) info lines, \(scored) scored" + (stopped ? ", stopped" : "")
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
    /// every line from its own `Task`, so a line can arrive out of order or not at all.
    /// The CI failures (2026-11-11) had `go` reach Stockfish (it printed the go-time
    /// info strings) and then no `bestmove` for 40 s. So a search that overruns is
    /// stopped, which forces a `bestmove`, and if that never comes either the search
    /// is run again. Each search's line counts go in the failure message, to tell a
    /// stalled search (no info lines) from dropped output (info lines, no bestmove).
    func testSearchesStartPositionWithBundledNets() async throws {
        let engine = Self.engine
        await engine.start()
        let stream = await engine.responseStream
        let responses = try XCTUnwrap(stream)

        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        let pump = Task {
            for await response in responses { sink.yield(.response(response)) }
        }
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                sink.yield(.tick)
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now + Self.deadline
        var readies = 0
        var strings: [String] = []
        var searches: [Search] = []
        var bestmove: String?

        func search() async {
            searches.append(Search(started: clock.now))
            await engine.send(command: .position(.startpos))
            await engine.send(command: .go(depth: Self.depth))
        }

        loop: for await event in events {
            switch event {
            case .response(.readyok):
                readies += 1
                if readies == 1 {
                    // ChessKitEngine has just sent its setup options (the nets among
                    // them); a second handshake makes sure Stockfish has loaded them.
                    await engine.send(command: .isready)
                } else if readies == 2 {
                    await search()
                }
            case .response(.info(let info)):
                if let string = info.string { strings.append(string) }
                guard !searches.isEmpty else { break }
                searches[searches.count - 1].infos += 1
                if info.depth != nil, info.score != nil { searches[searches.count - 1].scored += 1 }
            case .response(.bestmove(let move, _)):
                bestmove = move
                break loop
            case .response:
                break
            case .tick:
                let now = clock.now
                if now >= deadline { break loop }
                guard let current = searches.last else { break }
                if !current.stopped, now - current.started > Self.searchBudget {
                    searches[searches.count - 1].stopped = true
                    await engine.send(command: .stop)
                } else if current.stopped, now - current.started > Self.searchBudget + Self.stopBudget,
                          searches.count < Self.searches {
                    await search()
                }
            }
        }
        pump.cancel()
        ticker.cancel()
        sink.finish()
        await engine.send(command: .stop)

        let report = "searches: \(searches); info strings: \(strings)"
        await MainActor.run {
            XCTContext.runActivity(named: "Stockfish transcript") { activity in
                let attachment = XCTAttachment(string: report)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }

        XCTAssertEqual(readies, 2, "the handshake didn't finish; \(report)")
        let move = try XCTUnwrap(bestmove, "no bestmove; \(report)")
        XCTAssertFalse(move.isEmpty || move == "(none)", report)
        XCTAssertGreaterThan(searches.map(\.scored).reduce(0, +), 0, "no info line carried a score; \(report)")
        for net in Stockfish.nets.map(\.lastPathComponent) {
            XCTAssertTrue(strings.contains { $0.contains("NNUE evaluation using") && $0.contains(net) },
                          "Stockfish didn't report evaluating with \(net); \(report)")
        }
    }
}
