# Motif — iOS Eval Bar Plan

> Adds a Stockfish evaluation bar beside the board on the game screen. It
> follows the current position, like chess.com's game review: on every step the
> old search stops, and after a short pause the new position is analysed. The
> bar moves as the search goes deeper. Full-strength Stockfish runs on the
> device, so it works offline and for every position, including variations the
> user adds. The collection list doesn't change.
>
> **Mockup:** https://claude.ai/artifact/Mq9NRGsaK2tPoyKtN3PSwY, board
> **C · Beside the board**. Boards A and B were the list options, which were
> turned down.

---

## 1. Decisions (confirmed 2026-10-27)

1. **Beside the board only**, on `GameView`. No bar in the game collection
   list.
2. **Stockfish on the device, at full strength**: the big NNUE net plus the
   small one, both in the app bundle (~70–80 MB together, depending on the
   Stockfish version).
3. **Live, streaming evaluation.** The bar updates as each search depth
   completes. It doesn't wait for a final result.
4. **Stop at once, start after a pause.** Stepping to another position stops
   the running search straight away. The new search starts only after
   navigation has been idle for the debounce delay, so tapping Next/Previous
   quickly doesn't start and stop a search for every position on the way.
5. **License: GPL-3.** The Motif repo (public, no license today) gets a GPL-3
   `LICENSE`, and the app gets a Stockfish credit with a source link. There's
   nothing to apply for. This is only needed once builds go to anyone besides
   the owner, but it's done in E01 so it isn't forgotten.

## 2. Engine integration

- **Package:** [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine)
  (Swift wrapper for Stockfish, `Engine(type: .stockfish)`), added through
  Swift Package Manager and pinned to an exact release. It doesn't ship the
  NNUE files. After launch it needs the `EvalFile` and `EvalFileSmall` options
  set to paths in `Bundle.main`. It's the first project dependency to need C++,
  so E01 confirms it builds on the `macos-26` runner for the iOS 26.1
  simulator and for device archive. **Fallback** if it doesn't build or is
  stale: vendor a pinned Stockfish release in a local package
  (`iOS/Packages/StockfishKit`). It would be a C++ target with a small C
  bridge: `sf_start`, `sf_send(cmd)`, and an output callback fed by a
  `std::streambuf` that replaces `std::cout`. The rest of the plan stays the
  same, because the app only talks to the engine through the `UCIEngine`
  protocol (§3).
- **Nets:** use the two net names the pinned Stockfish version expects (from
  its `evaluate.h`; the package's README lists them per release). They're not
  committed to git, because of their size. `scripts/fetch-nnue.sh` downloads
  them from `https://tests.stockfishchess.org/api/nn/<name>` into
  `iOS/Motif/Motif/Engine/Nets/` (git-ignored). It checks each file's SHA-256
  against the prefix in its name and does nothing if the files are already
  present. `ios-ci.yml`, `ios-testflight.yml` and `scripts/ios-verify.sh` run
  it before building, with `actions/cache` keyed on the net names. A missing
  net fails the build. The app must never ship without one.
- **Engine settings:** `Threads` = active cores − 1 (minimum 1), dropping to 1
  when `ProcessInfo.thermalState` is `.serious` or worse. `Hash` = 128 MB.
  `MultiPV` = 1. One engine instance per app, started lazily the first time a
  game screen opens, and kept until memory pressure or until the app has spent
  60 s in the background.

## 3. Analysis service

New folder `Motif/Motif/Engine/` (synchronized, so the project file needs no
edit):

- **`UCI.swift`**: pure parsing, unit-tested. It reads `info` lines and keeps
  `depth`, `score cp N` / `score mate N` and the first `pv` move. It ignores
  `lowerbound`/`upperbound` lines and lines without a score, and reads
  `bestmove`. Scores are given for the side to move, so it converts them to
  **White's point of view** using the FEN's side to move.
- **`UCIEngine` protocol**: `send(_ command: String)` and an
  `AsyncStream<String>` of output lines. There's a ChessKitEngine adapter and a
  `FakeEngine` (tests and UI-test launch route) that replays scripted lines.
- **`Analyzer`** (`@MainActor @Observable`), owned by `GameContentView`. It
  exposes `evaluation: Evaluation?`, where `Evaluation` is `{ fen, depth,
  score: .cp(Int) | .mate(Int), final: Bool }`.
  - `show(fen:)` is called whenever `model.fen` changes:
    1. **Same FEN as the current job** → nothing.
    2. **Cached** (in-memory LRU, 256 FENs) at the target depth → publish it,
       no search.
    3. Otherwise **publish the cached partial result, or nil (bar stays where
       it was, label dims)**. If a search is running, **send `stop` now**.
       Then restart a **debounce timer (250 ms)**. Every further `show` inside
       those 250 ms restarts the timer and doesn't touch the engine.
    4. When the timer fires: wait until the stopped search has sent its
       `bestmove` (the engine must be idle before the next `position`). Then
       send `position fen <fen>` and `go depth 22 movetime 20000` (stop at
       depth 22 or after 20 s, whichever comes first; both are constants).
  - Every job has an id. Output lines are applied only to the job that is
    current; anything arriving between `stop` and `bestmove` is dropped.
    Partial `info` updates are throttled to about 10 per second, and each one
    updates the cache.
  - **No engine needed:** checkmate → ±mate result straight away (`M0`, bar
    full for the winner); stalemate and insufficient material → 0.0. Both use
    `Board` from `Model/`.
  - **Lifecycle:** `stop` on `onDisappear` and when `scenePhase` leaves
    `.active`; resume the current FEN when the screen becomes active again.
    The bar toggle (§4) set to off → `stop` and no new searches.

## 4. The bar

- **Placement:** a vertical bar on the leading side of the board, 16 pt wide
  with a 4 pt gap and 4 pt corner radius, exactly the board's height. The
  board's width is the space that remains (`min(width − 20, height × 0.6)`), so
  the move list and toolbars keep their layout.
- **Fill:** White's part = `50 + 50 × (2 / (1 + exp(−0.00368208 × cp)) − 1)`
  percent (Lichess's win-chance curve), clamped to 2–98 % so the losing side
  stays visible. Mate → 100 % / 0 %. White's part is at the bottom when White
  is at the bottom of the board, and it flips with **Flip board**. Changes
  animate with `.smooth(duration: 0.35)`.
- **Colours:** White's part `#F4F4F4`, Black's part `#3A3A3C` in light and dark
  mode alike, with a 0.5 pt hairline so the light part shows against the dark
  background.
- **Label:** `0.6` / `M3` (no sign: the end it sits at shows who's ahead) in
  9 pt semibold monospaced digits, inside the leading side's part, at the end
  nearest that player. It shows at 50 % opacity until depth 12 and fully after
  that. Before the first result for a position, the bar keeps its last fill
  and the label shows `…`.
- **Toggle:** the game ⋯ menu gets **Show Evaluation** / **Hide Evaluation**
  (`@AppStorage("evalBarShown")`, default on). Hidden → the board takes the
  full width again and no search runs.
- **Accessibility:** one element, label "Evaluation", value e.g. "White is
  better by 0.6, depth 18" / "Black mates in 3" / "Equal" / "Analysing".
  Identifier `eval-bar`. It isn't announced on every update.
- **Unreadable game, no tree:** no bar.

## 5. Implementation slices

Each slice is one PR with `MotifTests` + `MotifUITests` green.

| Slice | Scope | Main files |
|---|---|---|
| **E01** Engine in the build | ChessKitEngine pinned (or the vendored fallback), `fetch-nnue.sh`, CI/TestFlight/verify steps + cache, `.gitignore`, GPL-3 `LICENSE`, Stockfish credit in the Account sheet | `project.pbxproj` (package ref), `scripts/`, `.github/workflows/`, `AccountView` |
| **E02** Analyzer | `UCI.swift`, `UCIEngine` + adapter + `FakeEngine`, `Analyzer` (debounce, stop/wait/start, job ids, cache, throttle, terminal positions, lifecycle) | `Motif/Engine/*`, `MotifTests/Engine/*` |
| **E03** Eval bar UI | `EvalBar` view, `GameView` layout, flip, toggle in ⋯ menu, accessibility, debug route `game-eval` using `FakeEngine` | `UI/Games/EvalBar.swift`, `GameView`, `AppState` routes, `MotifUITests` |

They run in order: E02 needs the engine from E01, and E03 needs the
`Analyzer`.

## 6. Tests

- **E01:** a `MotifTests` case starts the real engine in the simulator, sends
  `position startpos` + `go depth 10`, and expects `info … score` lines and a
  `bestmove` within 10 s. It also checks that both nets are in the bundle.
- **E02** (all with `FakeEngine` and an injected clock, no real engine):
  - The parser handles cp, mate, negative mate, bound lines, missing score and
    the side-to-move flip.
  - Five `show` calls 50 ms apart → one `stop`, exactly one `go`, for the last
    FEN.
  - `go` is never sent before the stopped job's `bestmove`.
  - Lines from a stopped job never reach `evaluation`.
  - A cached FEN at the target depth → no `go`.
  - Checkmate/stalemate → no engine traffic.
  - Leaving `.active` → `stop`.
- **E03:** the UI test opens the `game-eval` route and finds `eval-bar` with
  the scripted value. Stepping Next → the value changes after the debounce.
  Hide Evaluation → `eval-bar` is gone, and it stays gone after relaunch.
  Screenshots in light and dark mode are compared against mockup board C.

---

## 7. Running the slices

Same driver as the UI refresh: **one fresh Claude session per slice**, branch
`ios-eval/Exx`, PR, `ios-ci` green, merge.

- **Unattended:** from a clean, dedicated checkout on `main`:
  `scripts/run-ios-eval-prompts.sh` (or `… E02` to resume).
- **By hand:** open a new session in the repo, paste the slice's **Run** line,
  review the PR, merge.

### Shared rules (inlined into every slice)

> 1. **§1–§4 are the spec.** Don't change `Model/`, `Data/`, or the behaviour
>    `src/` defines. The analyzer may *read* `Board`/`fenAt`, nothing more.
> 2. **The engine is reached only through `UCIEngine`.** No view talks to
>    ChessKitEngine directly.
> 3. **Never block the main actor** on engine output. Parsing happens off the
>    main actor, and only `Evaluation` values hop to it.
> 4. **Keep the accessibility identifiers** the UI tests use, and update
>    `MotifUITests` in the same slice for anything you move.
> 5. **Synchronized folders:** new files under `Motif/`, `MotifTests/` and
>    `MotifUITests/` need no `project.pbxproj` edit. The package reference
>    (E01) does.
> 6. **No Mac, so CI is the compiler.** Done = `ios-ci` green + the slice's
>    "Done when" + nothing from a later slice.

### E01 — Engine in the build

**Run:**
> In this repo, read `Motif - iOS Eval Bar Plan.md` §1, §2, §6 and §7 → **E01**.
> Add Stockfish to the iOS app with its full-strength NNUE nets fetched at build
> time, add the GPL-3 license and the Stockfish credit. Get `ios-ci` green.

**Build:**
- Add the ChessKitEngine package, pinned to an exact version. Check its README
  for that version's net names and the `EvalFile`/`EvalFileSmall` setup. If it
  doesn't build on `macos-26` for the simulator and for archive, switch to the
  vendored `StockfishKit` fallback and say so in the PR.
- `scripts/fetch-nnue.sh` (names in one place, SHA-256 check, does nothing if
  already present). Run it from `ios-ci.yml`, `ios-testflight.yml` and
  `scripts/ios-verify.sh`, with caching. Git-ignore `Engine/Nets/`.
- `LICENSE` (GPL-3.0 text). In the Account sheet, an "Acknowledgements" row
  with: "Evaluation by Stockfish, licensed under GPL-3.0" and links to the
  Stockfish and Motif source.
- The §6 engine smoke test.

**Out of scope:** any analyzer or UI on the game screen.
**Done when:** the smoke test passes in CI, and a TestFlight build from `main`
archives with both nets inside.

### E02 — Analyzer

**Run:**
> In this repo, read `Motif - iOS Eval Bar Plan.md` §3, §6 and §7 → **E02**.
> Build the UCI parser, the `UCIEngine` protocol with its adapter and
> `FakeEngine`, and the `Analyzer` with stop-now / debounce / wait-for-bestmove
> / cache / throttle. Get `ios-ci` green.

**Build:** everything in §3. The debounce, throttle, depth, time and cache size
are named constants. The clock is injected so the tests don't sleep.
**Out of scope:** drawing the bar. `GameView` may create the analyzer but shows
nothing.
**Done when:** every §6 E02 case passes; CI green.

### E03 — Eval bar UI

**Run:**
> In this repo, read `Motif - iOS Eval Bar Plan.md` §4, §6 and §7 → **E03**. Draw
> the evaluation bar beside the board on the game screen, driven by the
> `Analyzer`, with the Show/Hide toggle and the `game-eval` debug route. Get
> `ios-ci` green.

**Mockups:** board `C · Beside the board`.
**Build:** `UI/Games/EvalBar.swift` and the `GameView` layout change (§4).
Orientation follows `model.orientation`. Add the ⋯ menu toggle,
accessibility, and the `game-eval` launch route, which swaps in `FakeEngine`
with a scripted climb from depth 1 to 22 at +0.6.
**Out of scope:** the collection list, PGN `[%eval]` import, best-move arrows.
**Done when:** the §6 E03 UI test passes; no layout change on the game screen
when the bar is hidden; CI green.
