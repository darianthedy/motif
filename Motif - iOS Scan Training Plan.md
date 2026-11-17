# Motif — iOS Scan Training Plan

> How to build Scan Training Mode on iOS. The requirements are in
> `Motif - Scan Training Mode.md` (source doc:
> https://claude.ai/artifact/BjDma8oLeUdfUGR2dUidtD). This plan doesn't
> change them; where it has to pick something they leave open, the pick is
> listed under §11 Open questions.
>
> In short: a Python script on the Mac Mini works out every answer ahead of
> time with python-chess and Stockfish and uploads the puzzles to two new
> tables. The app only compares taps, arrows and moves with those stored
> answers. `BoardView` gets annotation modes and one `Canvas` overlay, and a
> new `ScanSolveModel` runs the steps, timers and grading.

---

## 1. Decisions

1. **Separate content, separate tables.** Scan puzzles aren't rows in
   `puzzles`, and scan attempts aren't rows in `attempts`. A scan puzzle
   carries a position *before* the opponent's move, the move itself and a
   graded answer for each step, which `puzzles` has no place for. Existing
   puzzle mode and game collections stay unchanged (Scope).
2. **All answers are precomputed** (Puzzle content and answers). The phone
   runs no engine for Scan Training, though Stockfish is already in the app
   for the eval bar. Grading only compares input with stored answers, so it
   is deterministic, offline and testable without an engine. That includes
   the flag: whether a position is Flag or No flag is a field of the puzzle
   (`answer.flagged`), decided by the puzzle maker; the app only compares
   the user's call with it.
3. **Move grading uses a stored eval per legal move.** The script stores the
   centipawn loss of *every* legal move in the start position (about 35
   moves, each ≤ 1 s of Stockfish). A move passes when its loss is within the
   pass margin: 50 cp (half a pawn) or less, or any move that keeps a
   forced mate (confirmed 2026-11-17). Example: best is +1.2, a move at +0.9
   passes, one at +0.4 fails. The one-line feedback reason can then say
   "loses 2.3" for any move played.
4. **iOS only.** The web app gets no Scan Training. The "web app is the spec"
   rule in `Motif - Tech Plan - iOS.md` doesn't apply to this feature: this
   plan is its spec.
5. **No fixed quiet ratio.** Each draw picks from the whole due pool at
   random, so the share of quiet positions follows the pool and changes as it
   grows. No pattern, no streak rule (Puzzle flow, last paragraph).
6. **"Flag" is a scan word only.** `puzzles.flagged` already means "needs a
   look". Scan code says `flagCall` (what the user called) and `flagged`
   only on `ScanAnswer` (what the position is), never on a `Puzzle`.
7. **Its own tab for the prototype.** Scan Training is a third tab, **Scan**,
   beside Puzzles and Games (confirmed 2026-11-17). It may move into Puzzles
   later; §6 keeps its views independent of the tab so that move is small.
8. **Native iOS, built to the project's design rules.** SwiftUI only, no new
   packages, deployment target stays iOS 26.1 (iOS 27 APIs behind
   `#available`). Every screen follows the Apple HIG review (`apple-design`
   skill) and the SwiftUI rules (`swiftui-pro` skill); §7 lists what that
   means for this feature, and each slice is checked against it.

## 2. Data

`db/0003_scan.sql`, the same rules as `0001_schema.sql`: `user_id` on every
row, row-level security, foreign keys that include `user_id`, safe to re-run.

```sql
create table if not exists public.scan_puzzles (
  id          uuid        primary key,
  user_id     text        not null default auth.user_id(),
  -- 'own' | 'lichess' | 'quiet'
  source      text        not null check (source in ('own', 'lichess', 'quiet')),
  -- Lichess puzzle id, or game id + ply, for re-imports and for linking back.
  source_id   text,
  fen_before  text        not null,   -- before the opponent's last move
  last_move   text        not null,   -- UCI
  answer      jsonb       not null,   -- ScanAnswer, §2.1
  version     integer     not null,   -- answer format version
  added_at    timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, source, source_id)
);

-- Insert-only, id made on the device: the outbox can always retry.
create table if not exists public.scan_attempts (
  id          uuid        primary key,
  user_id     text        not null default auth.user_id(),
  puzzle_id   uuid        not null,
  result      text        not null check (result in ('pass', 'fail')),
  flag_call   boolean     not null,
  -- Per step: ms taken, limit in force (null while timing is record-only),
  -- missed and extra squares/arrows. ScanAttemptDetail, §2.2.
  detail      jsonb       not null,
  played_at   timestamptz not null,
  foreign key (user_id, puzzle_id)
    references public.scan_puzzles (user_id, id) on delete cascade
);
```

Grants: `scan_puzzles` select/insert/update/delete (re-import updates
`answer`); `scan_attempts` select/insert/delete, never update.

### 2.1 `ScanAnswer` (stored as `answer`)

```json
{
  "flagged": true,
  "flagReasons": ["quickScan", "inCheck", "winning"],
  "quickScan": [
    { "square": "f7", "kind": "attacked" },
    { "square": "d1", "kind": "opened" },
    { "square": "c6", "kind": "undefended" }
  ],
  "targets": {
    "red": ["f7"], "orange": ["e5"],
    "kingZone": ["g7", "h7"], "fork": ["d5"]
  },
  "arrows": [
    { "from": "c4", "to": "f7", "side": "own", "kind": "capture" },
    { "from": "d8", "to": "h4", "side": "theirs", "kind": "threat" }
  ],
  "moves": { "e1g1": 0, "c4f7": -12, "d2d3": 85 },
  "bestLine": ["c4f7", "e8f7", "f3g5"]
}
```

`moves` maps every legal move to its centipawn loss against the best move
(mates as ±100000 minus the mate distance). `targets` and `arrows` are empty
until v2 content is generated; v1 puzzles get them on a re-run, and the
`version` column says which steps a puzzle supports.

### 2.2 `ScanAttemptDetail` (stored as `detail`)

```json
{
  "steps": {
    "quickScan": { "ms": 7400, "limitMs": null, "missed": ["c6"], "extra": [] },
    "move":      { "ms": 3100, "limitMs": null, "played": "c4f7", "lossCp": 12 }
  },
  "softMisses": ["quickScanMissed"],
  "failReason": null
}
```

Stats (v2) read only this, so nothing in it is a summary that can go stale.

### 2.3 On the device

`Library` gets `scanPuzzles: [ScanPuzzle]` and `scanAttempts: [ScanAttempt]`,
loaded with the rest by `Backend.load()`. `Backend` gets
`recordScanAttempts(_:)`, and `OutboxRecords` gets `scanAttempts`, flushed the
same way as `attempts` so an attempt made offline is never lost.
`MemoryBackend` gets the same, for tests and fixtures.

## 3. Content pipeline (Mac Mini)

`scripts/scan/` in Python 3, run with `-I`, using python-chess and the
Homebrew `stockfish` binary. It reuses the Neon sign-in from
`scripts/motif-db.py` (moved into `scripts/motif_auth.py` so both import it),
prints what it would write, and writes only with `--apply`.

```
scripts/scan/build.py own   --since 2026-10-01 [--apply]   # from game collections
scripts/scan/build.py lichess lichess_db_puzzle.csv --rating 1400-2000 --count 300 [--apply]
scripts/scan/build.py quiet  --from-own --count 100 [--apply]
scripts/scan/build.py regrade [--apply]   # re-run answers for every stored puzzle
```

**Sources.**

- **Own games:** read the PGNs from `games`, analyse each of the owner's
  moves (depth 18), and take every move that loses ≥ 2.0 (or misses a mate).
  The puzzle is the position after the opponent's move before it:
  `fen_before` = before that opponent move, `last_move` = the opponent move.
  The owner's side is read from the PGN `White`/`Black` headers.
- **Lichess:** the CSV's `FEN` is already before the opponent's move and the
  first UCI in `Moves` is that move, so `fen_before = FEN`,
  `last_move = Moves[0]`. Filter by rating and theme.
- **Quiet:** positions from own games where |eval| ≤ 0.5, the best and
  second-best moves are within 0.3, and the flag rule (below) comes out false.

**Answers** (`scripts/scan/answers.py`, pure functions over a `chess.Board`,
each with pytest cases):

- **Quick scan.** With `M` the opponent's move:
  - *attacked*: the solver's pieces attacked by the moved piece on its
    to-square that it didn't attack from its from-square.
  - *opened*: the solver's pieces newly attacked by the opponent's line
    pieces through the from-square (discovered attacks).
  - *undefended*: the opponent's pieces the moved piece defended before `M`
    that now have no defender.
  - Castling counts the rook as a moved piece too; en passant counts the
    captured pawn's square as opened.
- **Flag** = any quick-scan square, or side to move in check, or eval for
  the side to move ≥ +3.0. The reasons go in `flagReasons`. Only "real
  trouble" counts as a quick-scan square for the flag: a piece attacked by
  something cheaper, or attacked more often than defended (§11.1). The
  maker can override any puzzle by hand in `scripts/scan/overrides.json`
  (`{"<source>:<source_id>": {"flagged": false}}`); an override wins on
  every re-run and is recorded as the reason `manual`.
- **Targets** (v2): attackers and defenders per piece, with SEE. *Red* = a
  capture there wins material, *orange* = an even 1–1 trade. *King zone* =
  squares next to either king that the other side attacks. *Fork* = empty
  squares a knight, pawn or queen of either side can reach in one move from
  which it attacks two pieces worth more than itself, or a piece and the
  king.
- **Arrows** (v2), both sides, one move deep: checks; captures with SEE > 0
  or that mate; threats found with a null move: after
  `board.push(chess.Move.null())`, the opponent's moves that win ≥ 1.5 at
  depth 12. Only these are graded; extra arrows aren't.
- **Moves:** Stockfish `multipv` over all legal moves, depth 18, cached by
  FEN in `~/.cache/motif-scan/` so re-runs are fast.

Every generated puzzle is replayed through python-chess before upload
(`last_move` legal from `fen_before`, every answer square on the board).

## 4. Board

`BoardView` today is 64 SwiftUI `Button`s with a drag gesture per square,
driven by `BoardInteraction`. Scan Training adds, without changing what
`.play` does for every existing caller:

```swift
enum BoardMode: Equatable { case play, markSquares, markTargets, drawArrows }

struct BoardAnnotations: Equatable {
    var tints: [String: SquareMark] = [:]    // quick-scan highlight, red, orange
    var dots: Set<String> = []               // king-zone / fork squares
    var rings: [String: RingStyle] = [:]     // feedback: correct, missed, extra
    var arrows: [BoardArrow] = []            // from, to, side, style
    var ghost: BoardGhost?                   // square + piece
}
```

Each type gets its own file under `UI/Board/` (`BoardMode.swift`,
`BoardAnnotations.swift`, `SquareMark.swift`, `RingStyle.swift`,
`BoardArrow.swift`, `BoardGhost.swift`, `BoardOverlay.swift`), and all are
`Equatable` so Observation skips equal writes.

New `BoardView` parameters, all defaulted: `mode = .play`,
`annotations = BoardAnnotations()`, `onSquare: (String) -> Void`,
`onSquares: ([String]) -> Void` (one drag over several squares),
`onArrow: (String, String) -> Void`, `onArrowTap: (Int) -> Void`.

- **Gesture routing.** Only `.play` goes through `BoardInteraction`. In the
  other modes the square stays a `Button` (never `onTapGesture`), its action
  calls `onSquare`, and the drag gesture does what the mode says: in
  `.markSquares` nothing (taps only, pieces can't be selected); in
  `.markTargets` every square crossed goes to `onSquares` once at the end; in
  `.drawArrows` a drag that starts on a piece shows a preview arrow and calls
  `onArrow(from, to)` on release, and no piece moves. A tap within 12 pt of an
  arrow's shaft calls `onArrowTap` instead of `onSquare`. This keeps one
  meaning per gesture per step (Mobile UX).
- **Every drag has a tap equivalent** (`gestures.md › Custom gestures`: a
  custom gesture must not be "the only way to perform an important action";
  `accessibility.md › Mobility`: "Offer alternatives to gestures"). Marking
  several targets is the same as tapping each one. An arrow is also drawn by
  tapping a piece, then a square: the piece shows the existing selection
  tint while it waits, and tapping it again cancels.
- **Overlay.** One `Canvas` above the squares, `allowsHitTesting(false)`,
  draws tints, dots, rings and arrows in one pass. The drag point stays in the
  existing `DragPoint` observable, so a drag frame redraws the preview arrow,
  not the 64 squares. The ghost is the piece image in the squares layer at
  `.opacity(0.45)`.
- **Never colour alone** (`accessibility.md › Vision`: "Convey information
  with more than color alone"; red–green and blue–orange are the pairs it
  names). Each mark has a shape as well as a colour, always, not only when
  Differentiate Without Color is on:
  - Quick-scan highlight: accent tint plus a corner notch.
  - Red target: filled red tint plus `exclamationmark` in the corner.
  - Orange target: orange outline (no fill) plus `equal` in the corner.
  - Arrows: own side solid, their side dashed, as well as blue / orange.
  - Feedback: green solid ring with `checkmark`, missed dashed ring, extra
    grey ring with `xmark`.

  Colours are asset-catalog colours with light, dark and increased-contrast
  variants (`color.md › Best practices`), added to the shared design
  constants with the board colours, not literals in the overlay.
- **Haptics.** `.sensoryFeedback(.selection)` when a mark changes, matching
  its documented meaning ("feedback while the values of a UI element are
  changing", `playing-haptics.md › Selection`); a drag over several squares
  plays it once at the end, not per square, so it isn't overused
  (`› Avoid overusing haptics`). Grading plays `.success` / `.error` once per
  step. `sensoryFeedback` already follows the system haptics setting.
- **Reduce Motion.** With `accessibilityReduceMotion` on, the opponent's last
  move fades in place instead of sliding (`motion.md › Make motion optional`),
  and nothing waits for an animation to finish before the step can start
  (`› Let people cancel motion`).
- **VoiceOver.** Each square's label adds its mark ("f7, Black pawn, marked
  red, loses material"). In `.drawArrows` the two-tap path above is the
  VoiceOver path, and drawn arrows are listed below the board as buttons
  ("Arrow c4 to f7, check, delete") so they can be removed without hitting a
  shaft.
- **Size.** Square controls are at least 44 pt. The board takes the width the
  layout gives it (no fixed width, no `UIScreen`); `BoardLayout` caps it on
  iPad and the iPhone Duo inner display as it does today.

## 5. Model

New files, one type per file, kept apart from the puzzle code they sit
beside. Every `@Observable` class is `@MainActor`; model types are
`Sendable`, `Codable` and `Equatable`.

- `Model/Scan/ScanPuzzle.swift`, `ScanAnswer.swift`, `ScanAttempt.swift`,
  `ScanAttemptDetail.swift`: the stored types, plus `ScanPuzzle.startFen`
  (`fen_before` with `last_move` applied).
- `Model/Scan/ScanGrader.swift`: pure functions, no state.
  `gradeQuickScan(tapped:answer:)` → missed and extra squares.
  `gradeFlag(called:answer:)` → pass, fail or soft miss.
  `gradeTargets`, `gradeArrows` → missed and extra, extras never counted
  against. `gradeMove(_:answer:margin:)` → pass/fail plus `lossCp`.
  `result(of:)` folds the steps into pass/fail and soft misses (Scoring).
- `Model/Scan/ScanQueue.swift`: what to show next. A puzzle is due when it
  has never been played, or by an interval that doubles from 1 day on each
  pass and goes back to 1 day after a fail. A fail is also put back into the
  current session `RETRY_GAP` (3) puzzles later, as `Runner` does. Picks
  from the due pool are uniform at random (§1.5).
- `Model/Scan/ScanTiming.swift`: per-step targets (10 / 5 / 20 / 15 / 10 s).
  Record-only until 14 days after the first scan attempt; after that a
  step's hard limit switches on once that step's median over the last 50
  attempts is under its target, and stays on. A **Time limits** switch in
  the Scan tab (on by default) turns hard limits off, and they start off
  while VoiceOver or Switch Control is running (`accessibility.md ›
  Cognitive`: "Minimize use of time-boxed interface elements";
  `swiftui-pro › accessibility`: respect the user's accessibility
  settings). Times are still recorded.
- `UI/Scan/ScanStep.swift`:

```swift
enum ScanStep: Equatable { case lastMove, quickScan, targets, arrows, move, finalCheck, done }
```

- `UI/Scan/ScanSolveModel.swift`: `@Observable @MainActor`, beside
  `SolveModel`. It owns the step, the board FEN, the annotations, the step's
  start time and limit, and the attempt being built. The step order comes
  from the Puzzle flow: `lastMove` → `quickScan` → (No flag) `move` / (Flag)
  `targets` → `arrows` → `move` → `finalCheck`, with `feedback` after each
  step, shown in the step's own view state rather than as a separate step.
  In v1 the Flag branch goes straight to `move`.
  - **Time** comes from the injected clock in `Engine/Analyzer.swift`
    (`AnalysisClock`), so tests step time instead of waiting. The model
    stores only the step's start and end dates; the timer bar draws itself
    from them (§6), so the model doesn't tick and nothing re-renders every
    frame. A limit is one `Task` sleeping until the deadline, cancelled when
    the step ends. When it runs out, the step ends as it stands: missing
    squares and arrows are soft misses, and a move not played is a fail.
  - **Undo** is a stack of the step's marks and arrows, registered with the
    environment's `UndoManager`, so shake to undo and the three-finger swipe
    work as well as the Undo button (`undo-and-redo.md › Mobile`: "Avoid
    redefining standard gestures for undo and redo"). The undo name says
    what goes ("Undo Arrow", "Undo Mark"). Undo never leaves the step.

## 6. Screens

All standard SwiftUI containers, so iPhone Duo bars, the fold and Liquid
Glass come from the system (`tab-bars.md`, `designing-for-iphone-duo.md ›
Best practices`: "If you use standard system components, you receive this
layout automatically").

- **Tab.** `AppTab` gets `case scan`; `RootView` adds
  `Tab("Scan", systemImage: "scope", value: .scan) { ScanHomeView() }`
  between Puzzles and Games. The tab is always shown, also with no puzzles
  (`tab-bars.md › Best practices`: "Don't disable or hide tab bar buttons").
- **`ScanHomeView`** (the tab's root) in a `NavigationStack`: how many
  puzzles are due, a **Start** button (`.buttonStyle(.glassProminent)`, the
  one prominent action), last session's result, and the **Time limits**
  switch. No puzzles yet → `ContentUnavailableView` saying how to add them
  (`scripts/scan/build.py`). v2 adds a Stats row. It reads the library from
  `AppState` like the other tabs and holds no session state, so moving it
  into Puzzles later only moves the view.
- **Session.** Start opens `ScanSessionView` with `.fullScreenCover(item:)`,
  as runs do with `SessionView`, keyed by a session value in `AppState`.
  The session view owns its `ScanSolveModel` with `@State`, created once
  per puzzle.
- **`ScanSessionView` layout.**
  - Navigation bar: the step as the title ("Quick scan", "Targets", "Checks,
    captures, threats", "Move", "Final check") and a **Done** button
    (`.cancellationAction`, `Button("Done", systemImage: "xmark")`) that ends
    the session; finished attempts are already saved.
  - Under it the timer: `ProgressView(timerInterval:countsDown:)` from the
    step's start and deadline, which animates itself with no model ticks.
    Record-only steps show elapsed time as
    `Text(start, style: .timer)` instead. Both have an accessibility label
    ("12 seconds left").
  - The board.
  - The step's actions in a `safeAreaInset(edge: .bottom)`: Flag / No flag,
    or Next, as full-width `Button`s with text and a symbol
    (`Button("Flag", systemImage: "flag.fill")`). The finishing action is
    `.glassProminent`, the other `.glass`. Undo is a
    `ToolbarItem(placement: .bottomBar)` with
    `Button("Undo", systemImage: "arrow.uturn.backward")`, disabled when the
    step has nothing to undo, so it moves into the iPhone Duo vertical bar
    with the system's other items.
  - Text is Dynamic Type styles only (`.headline` step, `.body` reasons, no
    `.caption2`), no fixed padding or font sizes. At accessibility text
    sizes the action row stacks vertically through `ViewThatFits`.
- **Wide layouts.** With regular width (iPad, iPhone Duo inner display,
  landscape) the step panel sits beside the board instead of under it,
  chosen by `horizontalSizeClass`, never by device or orientation. Every
  control exists at every size (`designing-for-iphone-duo.md`: "Maintain the
  same functionality across device poses"). Checked on the outer display,
  inner display, a partial fold and Split View, per the existing Duo plan.
- **Per step.**
  - *Last move:* the board starts at `fen_before`; the move plays after
    450 ms (`REPLY_MS`) and stays highlighted. The timer starts.
  - *Quick scan:* `.markSquares`. Flag / No flag end the step.
  - *Targets:* `.markTargets`. Tap a piece for red → orange → clear, tap an
    empty square for a dot, drag to mark several. Next ends the step.
  - *Checks, captures, threats:* `.drawArrows`. Tap an arrow to delete it.
  - *Move:* `.play`. In v2 the move is shown ghosted and a sheet
    (`.sheet(item:)`, `.presentationDetents([.medium])`) asks "Their checks
    after this? What does this piece stop guarding?" with **Play It**
    (`.glassProminent`) and **Take Back**. Swiping the sheet down is Take
    Back, so it always has a way out (`sheets.md › Best practices`). In v1
    the move plays at once.
  - *Feedback:* inline, never an alert (`feedback.md`): the answer as marked
    rings on the board, a `Label` with a pass/fail symbol and the one-line
    reason ("Missed: Bxf7 hit the pawn on f7"), and **Continue**. VoiceOver
    reads the result with `AccessibilityNotification.Announcement`.
- **Titles and labels** use title-style capitals for buttons ("Play It",
  "Take Back", "No Flag"), as the HIG does on iOS (`writing.md`).

## 7. Design and SwiftUI checklist

What each slice is checked against before its PR, from the `apple-design`
review and the `swiftui-pro` rules:

1. One type per Swift file, in `Model/Scan/`, `UI/Scan/` and `UI/Board/`.
2. `@Observable @MainActor` models owned with `@State`, passed with
   `@Bindable` or `@Environment`; no `ObservableObject`. Timer ticks, drag
   points and geometry stay out of the environment.
3. Every tappable thing is a `Button` with a text label, at least 44 × 44 pt;
   icon-only looks use `.labelStyle(.iconOnly)`.
4. No information by colour alone (§4); asset-catalog colours with dark and
   increased-contrast variants.
5. Dynamic Type styles only; the session works at the largest
   accessibility size.
6. Reduce Motion, VoiceOver, Switch Control and the time-limit switch
   handled (§4, §5).
7. Standard `TabView`, `NavigationStack`, toolbar items, sheets with detents
   and `ContentUnavailableView`; nothing hand-built that the system offers.
8. Layout by size class, no fixed widths, no `UIScreen`; checked on iPhone,
   iPad and iPhone Duo (both displays, partial fold, Split View) with
   `scripts/ios-duo-capture.sh`.
9. iOS 27 / 27.1 APIs only behind `#available`; the target stays iOS 26.1.
10. `.coordinateSpace(.named(...))`, not the soft-deprecated
    `coordinateSpace(name:)`; the board's existing call is updated when S03
    touches it.

## 8. Stats and Caïssa export (v2)

`ScanStatsView`, pushed from the Scan tab, computed on the device from
`scanAttempts`: median quick-scan time, flag accuracy (calls right / all),
the most-missed category (quick-scan kind, target colour, arrow kind), and a
weekly trend line in Swift Charts with an accessibility chart descriptor.
**Export for Caïssa** shares a short Markdown summary of the same numbers
plus the 10 most recent fails (FEN, last move, what was missed) through
`ShareLink`.

## 9. Implementation slices

Each slice ends with `scripts/ios-verify.sh` green, the §7 checklist passed,
screenshots on iPhone and iPhone Duo, and its own PR.

**v1**

1. **S01 — Schema and pipeline.** `db/0003_scan.sql`; `scripts/scan/` with
   quick scan, flag and move answers; own, Lichess and quiet sources;
   pytest cases. Upload a first set of ~200 puzzles and report the flag
   rate (§11.2).
2. **S02 — Model.** The stored types, `ScanGrader`, `ScanQueue`,
   `ScanTiming` (record-only), `Backend`/`MemoryBackend`/`Outbox` support,
   unit tests.
3. **S03 — Board modes.** `BoardMode`, `BoardAnnotations`, the `Canvas`
   overlay, `.markSquares` routing, the mark shapes. A debug launch route
   `scan-board` like `board`. Existing board tests stay green unchanged.
4. **S04 — Scan tab and session.** `AppTab.scan`, `ScanHomeView`,
   `ScanSolveModel` and `ScanSessionView` for last move, quick scan, flag
   call, move and feedback; undo; a UI test for one flagged and one quiet
   puzzle.

**v2**

5. **S05 — Full-scan answers.** Targets and arrows in the pipeline,
   `regrade` over stored puzzles.
6. **S06 — Target and arrow modes.** `.markTargets`, `.drawArrows`, the
   two-tap arrow, arrow hit-testing, the VoiceOver arrow list.
7. **S07 — Final check.** Ghosted move, the Play It / Take Back sheet.
8. **S08 — Hard limits.** `ScanTiming` switching limits on, the Time limits
   switch.
9. **S09 — Stats and export.**

## 10. Tests

- **Pipeline (pytest):** fixed FENs for each quick-scan kind, castling (rook
  counted), en passant, promotion, discovered check; flag reasons; a quiet
  position that must not flag; SEE red vs orange; a null-move threat.
- **Grader:** table tests over fixture answers in
  `MotifTests/Fixtures/scan/`, written by the pipeline, so Swift and Python
  read the same files.
- **Queue and timing:** a seeded random source and a fake clock; the 14-day
  switch, the median rule at its edges, limits off with the switch off or
  VoiceOver on.
- **`ScanSolveModel`:** each branch of the step order, a limit running out
  mid-step, undo through `UndoManager`, an attempt saved through the outbox
  while offline.
- **Board:** `.play` behaves exactly as before (existing tests); in each new
  mode, a tap or a drag calls only its callback and never moves a piece; the
  two-tap arrow equals the drag.
- **UI:** one test per session path with fixture puzzles; screenshots of
  each step on iPhone and iPhone Duo via `scripts/ios-screenshot.sh` and
  `scripts/ios-duo-capture.sh`, including the largest text size and dark
  mode.

## 11. Open questions

1. **The puzzle maker's flag rule.** The flag is stored in each puzzle
   (§1.2); this question is only how `scripts/scan/` decides it. Read
   literally, "the quick scan found something" is true after almost every
   move (a knight move usually hits some well-defended pawn), so nearly
   every puzzle would be Flag and the call would teach nothing. Proposed:
   only pieces in real trouble count (§3). S01 reports the flag rate on the
   first 200 puzzles before the app is built, so the rule can be tuned, and
   `overrides.json` fixes single puzzles.
2. **"Comes back sooner".** The doubling interval in §5 is a proposal.
3. **Caïssa summary format.** Markdown via the share sheet is a guess at
   what Caïssa reads best.
