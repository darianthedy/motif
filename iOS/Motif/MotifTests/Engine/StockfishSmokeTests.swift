import ChessKitEngine
import XCTest
@testable import Motif

/// The real engine in the simulator: both nets are bundled, Stockfish loads them and
/// a short search streams scores and ends in a best move.
final class StockfishSmokeTests: XCTestCase {
    /// Never released: a stopped or deinitialized ChessKitEngine closes the pipe it
    /// moved stdout onto, and the next write to stdout would raise SIGPIPE.
    private static let engine = Stockfish.makeEngine()

    private struct Transcript {
        var strings: [String] = []
        var scored = 0
        var bestmove: String?
        var searchTime: Duration?
    }

    func testBothNetsAreBundled() {
        let names = Stockfish.nets.map(\.lastPathComponent)
        XCTAssertEqual(names.count, 2, "expected the big and the small net, found \(names)")
        for url in Stockfish.nets {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            XCTAssertGreaterThan(size, 1_000_000, "\(url.lastPathComponent) looks truncated")
        }
    }

    func testSearchesStartPositionWithBundledNets() async throws {
        let engine = Self.engine
        await engine.start()
        let responses = await engine.responseStream
        let stream = try XCTUnwrap(responses)

        let run = Task { () -> Transcript in
            let clock = ContinuousClock()
            var transcript = Transcript(), readies = 0, started = clock.now
            for await response in stream {
                switch response {
                case .readyok:
                    readies += 1
                    if readies == 1 {
                        // ChessKitEngine has just sent its setup options (the nets among
                        // them); a second handshake makes sure Stockfish has loaded them.
                        await engine.send(command: .isready)
                    } else if readies == 2 {
                        started = clock.now
                        await engine.send(command: .position(.startpos))
                        await engine.send(command: .go(depth: 10))
                    }
                case .info(let info):
                    if let string = info.string { transcript.strings.append(string) }
                    if info.depth != nil, info.score != nil { transcript.scored += 1 }
                case .bestmove(let move, _):
                    transcript.bestmove = move
                    transcript.searchTime = clock.now - started
                    return transcript
                default:
                    break
                }
            }
            return transcript
        }
        // Loading the 75 MB net comes before the search's own 10 s budget.
        let watchdog = Task { try await Task.sleep(for: .seconds(40)); run.cancel() }
        let transcript = await run.value
        watchdog.cancel()

        let bestmove = try XCTUnwrap(transcript.bestmove, "no bestmove; info strings: \(transcript.strings)")
        XCTAssertFalse(bestmove.isEmpty || bestmove == "(none)")
        XCTAssertGreaterThan(transcript.scored, 0, "no info line carried a score")
        XCTAssertLessThan(try XCTUnwrap(transcript.searchTime), .seconds(10))
        for net in Stockfish.nets.map(\.lastPathComponent) {
            XCTAssertTrue(transcript.strings.contains { $0.contains("NNUE evaluation using") && $0.contains(net) },
                          "Stockfish didn't report evaluating with \(net): \(transcript.strings)")
        }
        await engine.send(command: .stop)
    }
}
