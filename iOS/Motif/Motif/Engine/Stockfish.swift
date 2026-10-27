import ChessKitEngine
import Foundation

/// The Stockfish build the app ships (through ChessKitEngine) and the NNUE nets it
/// evaluates with. `scripts/fetch-nnue.sh` downloads the nets into `Engine/Nets/`
/// before every build, and ChessKitEngine points `EvalFile`/`EvalFileSmall` at them
/// in the bundle by name when the engine starts. Views never use this directly; the
/// analyzer reaches the engine through `UCIEngine`.
enum Stockfish {
    /// The NNUE nets in the app bundle: the big one and the small one.
    static var nets: [URL] { Bundle.main.urls(forResourcesWithExtension: "nnue", subdirectory: nil) ?? [] }

    /// A new, unstarted engine. ChessKitEngine redirects the process's stdout into
    /// the engine's pipe on `start()` and closes it on `stop()` or deinit, so keep
    /// one for the app's lifetime rather than making one per use.
    static func makeEngine() -> Engine { Engine(type: .stockfish) }
}
