# Motif — iOS Scan Training Plan

> How to build Scan Training Mode on iOS. The requirements are in
> `Motif - Scan Training Mode.md` (source doc:
> https://claude.ai/artifact/BjDma8oLeUdfUGR2dUidtD). This plan doesn't
> change them; where it has to pick something they leave open, the pick is
> listed under §11 Open questions.
>
> In short: Motif doesn't make scan puzzles. The puzzle maker (Caïssa)
> works out every answer, including Flag or No flag, and hands the puzzles
> over as a JSON import file or by writing rows straight into the database.
> Motif defines that format, checks what it receives, stores it, and only
> compares taps, arrows and moves with the stored answers. `BoardView` gets
> annotation modes and one `Canvas` overlay, and a new `ScanSolveModel` runs
> the steps, timers and grading.
>
> **Spec v6 / format 6 (2026-11-19):** the graded Targets step is gone. The
> full path is Quick Scan (10 s) → CCT arrows (30 s) → move (10 s) → final
> check; the quick path is unchanged. Red / orange target marking stays as an
> ungraded aid inside the arrows step (tap marks, drag draws arrows): marks are
> never checked, scored, stored or compared on review. Answers have no
> `targets`; an older row's is ignored, and nothing is drawn from it. Older
> attempts' target steps still read, but count for nothing in Stats or
> Review. Sections below that describe the target step are history.
>
> **Format 7 (2026-11-20): play the line out** (Puzzle flow 8). A Flag puzzle
> may carry `solutions`, lines like a normal puzzle's, and any puzzle
> `bestCp`. A first move on a line plays the line out: the opponent's reply,
> then the solver's next move, until the line ends. A first move that passes
> but isn't on a line ends the puzzle as a pass. When the best move is clearly
> winning, a move is graded by the win chance it loses (§1.3). Puzzles without
> these fields stay one move, graded as before.
>
> **Spec v9 (2026-11-21): the call is Tactic / Quiet.** The buttons read
> **Tactic** and **Quiet** (were Flag / No Flag): from v9 a Tactic also covers
> tension already on the board (a tactical position, or an opponent threat the
> last move didn't create), so a Tactic puzzle may have an empty `quickScan`, and
> Tactic can be called with nothing marked. Data is unchanged: `flagged` true =
> Tactic, false = Quiet, format 7. Code identifiers (`flagged`, `flagCall`,
> `missedFlag`, `scan-flag`) keep the old word; older sections below use it too.

---

## 1. Decisions

1. **Separate content, separate tables.** Scan puzzles aren't rows in
   `puzzles`, and scan attempts aren't rows in `attempts`. A scan puzzle
   carries a position *before* the opponent's move, the move itself and a
   graded answer for each step, which `puzzles` has no place for. Existing
   puzzle mode and game collections stay unchanged (Scope).
2. **The puzzle maker owns the content; Motif owns the format.** Making
   puzzles (finding positions, running python-chess and Stockfish, deciding
   Flag or No flag, targets, arrows and move scores) is Caïssa's job and is
   not part of this plan. Motif publishes the format (§3), checks every
   puzzle it receives against the rules of chess, and stores it. The phone
   runs no engine for Scan Training, though Stockfish is already in the app
   for the eval bar: grading only compares input with stored answers, so it
   is deterministic, offline and testable without an engine.
3. **Move grading uses a score per legal move from the maker.** Each puzzle
   lists how much worse every legal move is than the best one, in
   centipawns. A move passes when it's within 50 cp (half a pawn), or keeps
   a forced mate (confirmed 2026-11-17). Example: best is +1.2, a move at
   +0.9 passes, one at +0.4 fails. Motif applies the margin, so changing it
   needs no new content. The one-line feedback reason can then say
   "loses 2.3" for any move played.
   **From format 7:** a first move that starts any of the puzzle's lines
   (`solutions`) always passes, whatever its score. When the best move is
   clearly winning (`bestCp` ≥ 300, Caïssa's "+3"), a move passes if it loses
   **under 10 points of win chance** instead of within 50 cp. That is the same
   formula and threshold as `caissa/tools/engine.py`: `win_pct(cp) = 50 + 50 ·
   (2 / (1 + e^(−0.00368208·cp)) − 1)` (Lichess's curve), and `check` calls a
   drop under 10 "fine" (10 is its INACCURACY line). Win chance lost =
   `win_pct(bestCp) − win_pct(bestCp − loss)`. The 50 cp margin still passes
   anything it passed before, and a move that keeps a forced mate still passes.
   Example (book #241): at +8, Qb4 0.66 behind Qa4 loses 1.3 points and passes.
   A move after the first is matched exactly against the lines that still fit
   (the normal puzzles' `Model/Trie.swift`: `buildTrie`, `findEdge`; no second
   matcher), so the table doesn't grade it.
4. **iOS only.** The web app gets no Scan Training. The "web app is the spec"
   rule in `Motif - Tech Plan - iOS.md` doesn't apply to this feature: this
   plan is its spec.
5. **No fixed quiet ratio.** Every session draws from the pool at random, so the share of quiet positions follows the content the maker
   sends. No pattern, no streak rule (Puzzle flow, last paragraph).
6. **"Flag" is a scan word only.** `puzzles.flagged` already means "needs a
   look". Scan code says `flagCall` (what the user called) and `flagged`
   only on `ScanAnswer` (what the position is), never on a `Puzzle`.
7. **Its own tab for the prototype.** Scan Training is a third tab, **Scan**,
   beside Puzzles and Games (confirmed 2026-11-17). It may move into Puzzles
   later; §6 keeps its views independent of the tab so that move is small.
8. **One pool, no collections; otherwise the Puzzles tab's persistence**
   (confirmed 2026-11-17). Every scan puzzle is in one pool. Sessions
   resume, progress comes from attempts, and play works offline through the
   cache and outbox (§2). Each puzzle keeps the maker's `source` label, so a
   filter by source can be added later without changing the data.
9. **Native iOS, built to the project's design rules.** SwiftUI only, no new
   packages, deployment target stays iOS 26.1 (iOS 27 APIs behind
   `#available`). Every screen follows the Apple HIG review (`apple-design`
   skill) and the SwiftUI rules (`swiftui-pro` skill); §7 lists what that
   means for this feature, and each slice is checked against it.

## 2. Data

Scan Training copies the Puzzles tab's model, minus collections: one
**pool** of puzzles, **runs** (sessions) that store only their fixed queue, and
**attempts** that are only ever inserted. Progress, status and where a run
has got to are all worked out from the attempts, exactly as
`README.md › Sessions` describes for puzzles. The same rules give the same
guarantees: resuming on another device is exact, two devices can't
conflict, and play works offline.

`db/0003_scan.sql`, the same rules as `0001_schema.sql`: `user_id` on every
row, row-level security, foreign keys that include `user_id`, safe to re-run.

```sql
create table if not exists public.scan_puzzles (
  id          uuid        primary key default gen_random_uuid(),
  user_id     text        not null default auth.user_id(),
  -- fen_before (first four fields) + last_move: the same position sent
  -- twice updates the row instead of adding a second one.
  content_key text        not null,
  fen_before  text        not null,   -- before the opponent's last move
  last_move   text        not null,   -- UCI
  answer      jsonb       not null,   -- ScanAnswer, §3.2
  version     integer     not null,   -- format version, §3
  -- The maker's own labels, shown in puzzle detail and usable as a filter
  -- later: 'own game', 'lichess', ...
  source      text,
  source_id   text,
  added_at    timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, content_key)
);

-- As `runs`: only what never changes after a run starts.
create table if not exists public.scan_runs (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  -- 'all' for the whole pool, or 'review'.
  scope      text        not null check (scope in ('all', 'review')),
  mode       text        not null check (mode in ('randomGlobal', 'reviewMistakes')),
  queue      uuid[]      not null,
  started_at timestamptz not null,
  unique (user_id, id),
  unique (user_id, scope)              -- one run per scope, as for puzzles
);

-- As `attempts`: insert-only, id made on the device, so the outbox can
-- always retry and uploading twice stores once.
create table if not exists public.scan_attempts (
  id         uuid        primary key,
  user_id    text        not null default auth.user_id(),
  puzzle_id  uuid        not null,
  run_id     uuid,
  result     text        not null check (result in ('solved', 'failed', 'skipped')),
  flag_call  boolean,                  -- null for a skip
  -- Per step: ms taken, limit in force (null while timing is record-only),
  -- missed and extra squares/arrows. ScanAttemptDetail, §2.1.
  detail     jsonb       not null,
  played_at  timestamptz not null,
  foreign key (user_id, puzzle_id)
    references public.scan_puzzles (user_id, id) on delete cascade,
  foreign key (user_id, run_id)
    references public.scan_runs (user_id, id) on delete set null (run_id)
);
```

Grants match their puzzle twins: puzzles select/insert/update/delete (a
re-sent puzzle updates `answer`); runs and attempts select/insert/delete,
never update. Deleting a puzzle takes its attempts with it, and a run
simply skips puzzles that no longer exist.

`result` uses the puzzle words on purpose (`solved` = passed, `failed`,
`skipped`), so the derive code in §2.3 serves both.

### 2.1 `ScanAttemptDetail` (stored as `detail`)

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

### 2.2 Progress and sessions (same rules as Puzzles)

- **Status** of a scan puzzle is its latest result: *new*, *solved* or *to
  review*. The Scan home shows the same Solved / To review / New card as a
  puzzle collection, for the whole pool.
- **A session is a run.** Starting one fixes its queue; leaving and coming
  back resumes at the same puzzle, on this device or another. There are two
  runs at most: the pool and Review. Starting another replaces it, and
  **Discard Session** deletes it.
- **Two modes**, taken from Puzzles: **Start** draws the whole pool at
  random with recently seen puzzles at the back (`orderForGlobalDraw`,
  `RECENT_MEMORY`), so quiet and flagged positions come in no fixed pattern
  (§1.5); **Review Mistakes** takes the puzzles whose latest result is
  failed, or a pass that missed an arrow or a quick-scan piece (playtests 3
  and 4: the scan is what's drilled; slow steps don't count, nor do target
  misses on pre-v6 attempts). Such a pass is still a pass in its run and in the
  stats; it just shows as *to review* until a clean pass.
- **Failed puzzles come back sooner** in two ways, both from Puzzles: once
  more in the same run after `RETRY_GAP` (3) others, at most `MAX_RETRIES`
  (10) waiting; and in Review until solved.
- **Skip** is an attempt with result `skipped`: the puzzle doesn't come back
  that run and counts as neither. A puzzle already failed on screen (a wrong
  Quiet, shown as Missed the Tactic, with the full scan still to run) is
  recorded as that fail instead (playtest 4).
- **Mid-puzzle state isn't saved**, as with puzzles: an attempt is written
  when the puzzle ends, i.e. as its result shows, not on Continue (playtest 4:
  closing the session on the result lost it); the puzzle stays on screen
  until Continue. Leaving in the middle of a scan resumes that puzzle
  from its last move, with fresh timers.
- **Reset Scan Progress** (Scan tab menu) deletes every scan run and attempt
  and leaves the puzzles alone. Puzzle progress isn't touched, and the
  Puzzles tab's reset doesn't touch scan progress.

### 2.3 On the device (offline)

The same pieces the Puzzles tab uses, extended rather than copied:

- **`Library`** gets `scanPuzzles`, `scanRuns` and
  `scanAttempts`, loaded with the rest by `Backend.load()`. The cache
  (`Data/Cache.swift`) stores the whole `Library`, so the offline copy
  includes Scan with no new cache code.
- **`OutboxRecords`** gets `scanRuns` and `scanAttempts`. Starting a run or
  finishing a puzzle goes into the outbox, which uploads on opening, on
  returning to the foreground, on reconnecting and after each puzzle, and
  `overlay(_:_:)` lays them on the server copy, so play works offline and
  nothing is lost.
- **Edits need a connection**, as for puzzles: importing, deleting a
  puzzle, discarding a session and
  resetting progress are written straight to the database and disabled
  offline with the same note.
- **`Backend`** gets `importScanPuzzles`, `deleteScanPuzzle`,
  `saveScanRun`, `deleteScanRun`, `recordScanAttempts` and
  `resetScanProgress`, in `Rest.swift` and `MemoryBackend.swift`.
- **Derive code is shared, not copied.** `puzzleRecords`, `statsFor`,
  `reviewIds`, `recentIds` and `runProgress` in `Model/Derive.swift` become
  generic over a small `RunAttempt` protocol (`puzzleId`, `runId`, `result`,
  `playedAt`) that both `Attempt` and `ScanAttempt` adopt, so retries,
  resume and progress behave identically in both tabs and keep their
  existing tests.

## 3. Puzzle format (the contract with the maker)

Written up for Caïssa in the README's Import
section (beside the puzzle file format), with a sample at `samples/scan-sample.json`. Version 1 covers the
v1 steps; `targets`, `arrows` are optional there and a puzzle without
them skips the full scan. Version 2 (S06) requires both on every Flag
puzzle and checks them against the position (§3.3); version 1 files and rows
still load under the version 1 rules.

### 3.1 Two ways in

- **Import file.** `{"version": 1, "scan": [ ... ]}` (a puzzle file has
  `"collection"` and `"puzzles"`, so the two can't be confused). The Scan
  tab's Import sheet, the same view as the Puzzles one, adds it to the
  pool. It shows "N added, M updated, K rejected" with the reason for each
  rejection, as puzzle imports do, and upserts on `content_key`, so
  re-sending a puzzle updates it and keeps its progress.
- **Direct database write.** Caïssa signs in as the account and writes
  `scan_puzzles` rows (with `version`) through Neon's Data API, as
  `scripts/motif-db.py` does for games, upserting on
  `(user_id, content_key)`. RLS keeps it to that account's rows. The app
  picks the rows up on its next load.

Both ways end in the same check (§3.3): an import file rejects a bad puzzle
before it's written; a bad row written directly is skipped on load and
logged, never shown half-working.

### 3.2 One puzzle

```json
{
  "fenBefore": "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
  "lastMove": "g8f6",
  "flagged": true,
  "quickScan": [
    { "square": "e4", "kind": "attacked" },
    { "square": "c6", "kind": "undefended" }
  ],
  "targets": {
    "red": ["f7"], "orange": ["e5"],
    "kingZone": ["g7", "h7"], "fork": ["d5"]
  },
  "arrows": [
    { "from": "f3", "to": "g5", "side": "own", "kind": "threat" },
    { "from": "f6", "to": "e4", "side": "theirs", "kind": "capture" }
  ],
  "moves": { "f3g5": 0, "d2d3": 35, "b1c3": 40, "c4f7": 310 },
  "bestLine": ["f3g5", "d7d5", "e4d5"],
  "source": "lichess",
  "sourceId": "00sHx"
}
```

- `fenBefore` + `lastMove`: the position before the opponent's move and
  that move. The solver is the side to move after it.
- `flagged`: the maker's call, Flag or No flag. Motif never works it out.
- `quickScan`: the squares the quick scan should find, each with a `kind`
  (`attacked`, `opened`, `undefended`; `unpinned` from v4, `hanging` from
  v5) used in the feedback reason.
- `arrows` (v2): what the full scan should find (`targets`, v2–v5, is
  ignored from v6). Arrow `kind` is
  `check`, `capture` or `threat`; `side` is `own` or `theirs`. Extra arrows
  aren't graded.
- `moves`: every legal move of the solver, with how many centipawns worse
  it is than the best (best = 0; a move that throws away a mate counts as
  100000). Every legal move must be present, so any move played can be
  graded.
- `bestLine`: shown after the move, optional.
- `solutions` (v7, optional, Flag puzzles only): `[[uci, ...], ...]`, one or
  more lines as in normal puzzles. Each line alternates both sides' moves,
  starting with the solver's first move after `lastMove`, and holds best
  moves only. Only the solver's choices branch (the maker picks the engine's
  top reply for the opponent), so a second line differs at a solver move. The
  maker's rule for where a line ends is in the requirements (Line, Where the
  line ends); Motif doesn't check it.
- `bestCp` (v7, optional): the best move's eval in centipawns from the
  solver's side, a forced mate = 100000. With `moves` it gives every move's
  eval (`bestCp − loss`), so the phone can work out win chance (§1.3).
- `source`, `sourceId`: the maker's labels, optional.

Both v7 fields are read only from version 7. A puzzle without them is one
move, graded as before.

What the requirements say about content (own games one move before a
blunder, Lichess puzzles started a move earlier, quiet positions within
0.5) is guidance for the maker, not something Motif checks.

### 3.3 What Motif checks

`Model/Scan/ScanImport.swift`, a pure function shared by the import sheet
and the loader, with unit tests. A puzzle is rejected, with the reason, if:

- `fenBefore` isn't a legal position, or `lastMove` isn't legal in it;
- any square isn't on the board, or an arrow doesn't start on a piece;
- `moves` is missing a legal move of the solver or lists an illegal one;
- `flagged` is missing, or `version` is newer than the app understands.

From version 2, also if:

- a Flag puzzle has no `arrows` (empty is fine; `targets` is no longer
  required or checked, v6);
- an arrow is listed twice, its `side` isn't the side of the piece it starts
  on, it isn't a legal move of that piece with its side to move ("one move
  deep", for both sides), a `capture` captures nothing, or a `check` gives no
  check.

From version 7, also if:

- `solutions` is on a No flag puzzle, has no lines, or has an empty line;
- a line isn't legal from the start position (`fenBefore` + `lastMove`),
  reported with the line, the move and the ply;
- `solutions` or `bestCp` is malformed (`bestCp` must be a whole number).

`ScanAnswer.hasFullScan` (Flag with both present) is what S07's step order
reads; `ScanAnswer.hasLine` says the move is played out.

`scripts/validate-external.ts` gets a `--scan` mode that runs the same
checks on a file, so Caïssa can test one before sending it.

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
  - Quick-scan mark: a green ring round the piece, no fill (playtest 4: a
    violet tint blended with the last-move highlight).
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
  `gradeArrows` → missed and extra (no `gradeTargets` since v6), extras never counted
  against. `gradeMove(_:answer:margin:)` → pass/fail plus `lossCp`, and
  `onLine` when it starts one of the lines (v7); `passes` adds the win-chance
  rule (`winPct`, `winPctLost`, `clearlyWinningCp` 300, `maxWinPctLost` 10).
  `gradeLineMove(_:at:)` matches a later move with `findEdge` on the lines'
  trie; `shownLine(_:fitting:)` is the line the feedback shows.
  `result(of:)` folds the steps into pass/fail and soft misses (Scoring); a
  line left early fails with reason `offLine`.
- **The line (v7).** `ScanStep.line` follows a first move on a line that has
  more to play. The opponent's reply comes after `REPLY_MS`, through the
  injected clock, and the board waits (`replying`). The solver's next move is
  matched exactly. A move off every line isn't played: the puzzle fails, the
  feedback says "The line was 1... Kd7 2. Ke1 …" and the result arrow shows
  the line's move. Later moves have no final check and no hard limit. Their
  time is recorded as `steps.line` (`ScanLineStep`: `ms`, the solver's
  `played` moves, `offLine`). A first move that passes but isn't on a line
  ends the puzzle: "Also works. The puzzle's line was …".
- No scan-only queue code: what comes next is `runProgress` over the scan
  run and its attempts (§2.3), queues are built with the existing
  `makeQueue` and `orderForGlobalDraw`.
- `Model/Scan/ScanTiming.swift`: per-step targets (quick scan 10 / quiet move 5 / arrows 30 / flagged
  move 10 s; v6 dropped the 20 s targets step and gave the arrows 30 s).
  Record-only until 14 days after the first scan attempt; after that a
  step's hard limit switches on once that step's median over the last 50
  attempts is under its target, and stays on. A **Time limits** switch in
  the Scan tab (on by default) turns hard limits off, and they start off
  while VoiceOver or Switch Control is running (`accessibility.md ›
  Cognitive`: "Minimize use of time-boxed interface elements";
  `swiftui-pro › accessibility`: respect the user's accessibility
  settings). Times are still recorded.
  Built in S09: `ScanTiming.earned` replays the attempts (skips ignored), so
  "stays on" needs no stored state and every device agrees. The limit is
  the target itself. The switch is a device preference (`@AppStorage`,
  unset = on unless VoiceOver or Switch Control is running; set by hand, it
  wins). Limits are fixed when a puzzle starts. A quick scan that runs out
  has no call and **fails the puzzle on any position** (confirmed
  2026-11-17): it ends there, with `flag_call` null and fail reason
  `noCall`. A step cut off is recorded with `timedOut: true` and `ms` = the
  limit, and counts as over its target.
- `UI/Scan/ScanStep.swift`:

```swift
enum ScanStep: Equatable { case lastMove, quickScan, arrows, move, finalCheck, done }
```

- `UI/Scan/ScanSolveModel.swift`: `@Observable @MainActor`, beside
  `SolveModel`. It owns the step, the board FEN, the annotations, the step's
  start time and limit, and the attempt being built. The step order comes
  from the Puzzle flow: `lastMove` → `quickScan` → (No flag) `move` / (Flag)
  `arrows` → `move` → `finalCheck`, with `feedback` after each
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
- **`ScanHomeView`**, the tab's root in a `NavigationStack` (one screen,
  so no split view): the Solved / To review / New card for the pool; a
  **Session in Progress** row with **Resume** and **Discard Session** when
  one is open, otherwise **Start** (`.glassProminent`, the one prominent
  action); **Review Mistakes** with its count; **All Puzzles** (list →
  detail showing the position, last move, the maker's answer and labels,
  with Delete, disabled offline). A toolbar menu holds Import, **Time
  limits** and Reset Scan Progress. No puzzles yet →
  `ContentUnavailableView` saying how to add them (import a file, or have
  Caïssa send them). v2 adds a Stats row.
- **Shared, not copied.** The stats card, session row and offline note move
  from `CollectionView.swift` to `UI/Shared/` so both tabs use one copy.
  The Scan views read the library from `AppState` and hold no session
  state, so moving Scan into Puzzles later moves views, not data.
- **Session.** Start or Resume sets `app.scanSession`, which opens
  `ScanSessionView` with `.fullScreenCover(item:)`, as `app.session` does
  for `SessionView`. It shows the run's progress bar and remaining count,
  and a **Skip** action. The view owns one `ScanSolveModel` per puzzle with
  `@State`; finishing a puzzle records its attempt through the outbox,
  then `runProgress` names the next.
- **`ScanSessionView` layout.**
  - Navigation bar: the step as the title ("Quick scan", "Checks,
    captures, threats", "Move", "Final check") and a **Done** button
    (`.cancellationAction`, `Button("Done", systemImage: "xmark")`) that ends
    the session; finished attempts are already saved.
  - Under it the timer: `ProgressView(timerInterval:countsDown:)` from the
    step's start and deadline, which animates itself with no model ticks.
    Record-only steps show elapsed time as
    `Text(start, style: .timer)` instead. Both have an accessibility label
    ("12 seconds left").
  - The board.
  - The step's actions in a `safeAreaInset(edge: .bottom)`: Tactic / Quiet,
    or Next, as full-width `Button`s with text and a symbol
    (`Button("Tactic", systemImage: "bolt.fill")`). The finishing action is
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
  - *Quick scan:* `.markSquares`, prompt "Last move: Re5". Tactic / Quiet
    end the step; Quiet is disabled while any square is marked; Tactic works with none (v9).
  - *Targets:* `.markTargets`. Tap a piece for red → orange → clear, an
    empty square next to a king for red → orange → dot → clear, any other
    empty square for a dot; drag to mark several. Next ends the step. The
    arrows step then shows the answer's targets, dimmed, not the marks.
  - *Checks, captures, threats:* `.drawArrows`. Drag from a piece to draw; delete from the arrow list.
    From v6 a **tap** marks a target (the old Targets step's cycle, as a
    thinking aid) and arrows are drawn by **drag only**: no tap-tap arrows and
    no tap-on-shaft delete (the arrow list deletes). Marks are drawn only,
    never graded or stored, get no rings on the feedback and aren't carried to
    the move. Undo covers both. The every-drag-has-a-tap rule (§4) is waived
    here: VoiceOver isn't a target for this step.
  - *Move:* `.play`. After a full scan (v2) the move isn't played at once:
    the board shows the position after it with the moved piece see-through,
    and the action row offers only **Take Back** (`.glass`) and **Play It**
    (`.glassProminent`), no questions and no sheet, so nothing covers the
    board being checked. The move step's clock runs on through the check,
    and take-backs are recorded as `move.takeBacks`. Quiet calls and v1 puzzles
    play the move at once.
  - *Feedback:* inline, never an alert (`feedback.md`): the answer as marked
    rings on the board, a `Label` with a pass/fail symbol, a terse reason
    only when the title and rings don't already say it ("Ne4 attacked.",
    "−0.3. Best: Kd7."), the time ("7.4 / 10 s"), and **Continue**. Prompts
    are as short ("Your move."): the step title says where you are. VoiceOver
    reads the result with `AccessibilityNotification.Announcement`.
- **Titles and labels** use title-style capitals for buttons ("Play It",
  "Take Back", "Play It"), as the HIG does on iOS (`writing.md`).

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
the most-missed category (quick-scan kind, arrow kind; target colours went with v6), and a
weekly trend line in Swift Charts with an accessibility chart descriptor, and the share of Tactic puzzles in the content.
**Export for Caïssa** shares a short Markdown summary of the same numbers
plus the 10 most recent fails (FEN, last move, what was missed) through
`ShareLink`.

Built in S10 (`Model/Scan/ScanStats.swift`, `ScanStatsExport.swift`; `UI/Scan/ScanStatsView.swift`,
a **Stats** row under All Puzzles):

- **Played** means solved or failed; skips count for nothing. Attempts whose puzzle is gone are
  left out.
- **Median quick scan** is over every quick scan played; one cut off by its limit counts at
  the limit, as `ScanTiming` counts it.
- **Call Accuracy** (Tactic / Quiet) is calls right over all played. A quick scan that ran out had no call, so it
  counts as wrong.
- **Missed** counts, per category, the squares or arrows each step played had to find and how
  many were missed, by the answer's labels (`ScanMissCategory`). A missed square the answer no
  longer has (the puzzle was re-sent) isn't counted. Most missed = most misses, then the higher
  rate, then the plan's order. A Quiet call has no arrows to miss. A pre-v6 attempt's target step isn't
  counted.
- **By week**: calendar weeks with play, the last 12, one metric at a time (Quick Scan,
  Calls, Solved) on a single line, the 10 s target as a dashed rule; touching a point shows its
  week. VoiceOver gets an `AXChartDescriptor` with a summary.
- **Export for Caïssa** (toolbar `ShareLink`, plain Markdown text): the figures, misses by
  category, a weekly table and the 10 most recent fails, each with `fenBefore`, the last move in
  SAN and UCI, the reason ("Bxf7 lost 3.1", "Quiet on a tactical position") and what was missed
  per step. Numbers and dates are in a fixed format, so the text doesn't depend on the device's
  language.
- Debug fixture `scan-history` (six weeks of attempts) and route `scan-stats`; Duo capture
  states S18k (Stats) and S18l (empty).

## 9. Implementation slices

Each slice ends with `scripts/ios-verify.sh` green, the §7 checklist passed,
screenshots on iPhone and iPhone Duo, and its own PR.

**v1**

1. **S01 — Schema and format.** `db/0003_scan.sql`, the format write-up and
   `samples/scan-sample.json`, `ScanImport` checks, the `--scan` mode of
   `validate-external.ts`. Hand the format to Caïssa so content can be made
   while the app is built.
2. **S02 — Model and persistence.** The stored types, `ScanGrader`,
   `ScanTiming` (record-only); `Derive.swift` made generic over
   `RunAttempt` (existing tests unchanged and green); `Library`, cache,
   `Outbox`, `Backend`/`Rest`/`MemoryBackend` support for scan puzzles, runs
   and attempts; unit tests.
3. **S03 — Board modes.** `BoardMode`, `BoardAnnotations`, the `Canvas`
   overlay, `.markSquares` routing, the mark shapes. A debug launch route
   `scan-board` like `board`. Existing board tests stay green unchanged.
4. **S04 — Scan tab.** `AppTab.scan`, `ScanHomeView`, All Puzzles and
   puzzle detail, the import sheet, the shared stats card and session row.
5. **S05 — Session.** `ScanSolveModel` and `ScanSessionView` for last
   move, quick scan, flag call, move and feedback; undo, skip, resume; a UI
   test for one flagged and one quiet puzzle, and one that plays offline,
   quits, resumes and uploads on reconnect.

**v2**

6. **S06 — Full-scan format.** `targets` and `arrows` required for
   puzzles that use the full scan, with their checks.
7. **S07 — Target and arrow modes.** `.markTargets`, `.drawArrows`, the
   two-tap arrow, arrow hit-testing, the VoiceOver arrow list.
8. **S08 — Final check.** Ghosted move, Play It / Take Back.
9. **S09 — Hard limits.** `ScanTiming` switching limits on, the Time limits
   switch.
10. **S10 — Stats and export.** `ScanStats`, `ScanStatsView` with the weekly
    chart, the Markdown export (§8).

## 10. Tests

- **Import checks:** one fixture per rejection reason in §3.3, plus
  castling, en passant and promotion as `lastMove`; a re-sent puzzle
  updates instead of duplicating; a bad row from the database is skipped.
- **Grader:** table tests over fixture puzzles in
  `MotifTests/Fixtures/scan/`, the same files `validate-external.ts --scan`
  reads in its tests.
- **Persistence:** the existing `Derive` tests run unchanged, plus the same
  cases over `ScanAttempt`: resume after leaving mid-run, a retry after
  `RETRY_GAP`, a skip, a deleted puzzle dropping out of a run, two devices
  on one run, Review holding only failed puzzles, scan reset leaving puzzle
  progress alone. Offline: a run started and played offline is in the
  outbox, survives a relaunch (cache), and uploads once on reconnect.
- **Timing:** a fake clock; the 14-day
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

1. **Flag rule, for the maker.** Not Motif's decision, but worth passing to
   Caïssa: read literally, "the quick scan found something" is true after
   almost every move, so nearly every puzzle would be Flag and the call
   would teach nothing. Counting only pieces in real trouble (attacked by
   something cheaper, or attacked more often than defended) keeps Flag
   meaningful. The Scan tab's stats show the share of Flag puzzles, so it's
   easy to see if it drifts.
2. **Caïssa summary format.** Markdown via the share sheet is a guess at
   what Caïssa reads best.
3. **"Clearly winning" (v7).** Neither the requirements nor `engine.py`
   give a number, so Motif uses `bestCp` ≥ 300 (Caïssa's "+3 trigger").
   Below it, 50 cp still decides; near 0 the two rules nearly agree anyway
   (10 points of win chance ≈ 54 cp).
4. **Line moves aren't timed against a target (v7).** Only the first move
   has a target and limit. The line's time is recorded (`steps.line.ms`) but
   isn't graded until the requirements give it a target.
