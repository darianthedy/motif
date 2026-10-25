# Motif — iOS Build Prompts

> Sequenced, **self-contained** prompts for building the iOS app from
> **`Motif - Tech Plan - iOS.md`** (the "iOS Tech Plan").
>
> Each prompt runs in its **own fresh Claude Code session** against the `motif`
> repo — by hand, or unattended via `scripts/run-ios-prompts.sh`. Each carries
> the rules it needs inline, so §0 below need not be pasted alongside it.

---

## How to use this document

1. Open a new session **in the `motif` repo**.
2. Paste the prompt's **Run** line (only that line). It tells Claude what to read and
   build; the rest of the prompt is there for Claude to read in this file.
3. Do prompts **in order**, **one per session**. Review → PR → green `ios-ci` → merge → next.
4. After each prompt the PR check (`ios-ci.yml`: simulator build + `MotifTests`) is green.
   There is no Mac and no local build: **CI is the compiler.** Push the branch, read the
   check, fix, repeat.

### On a Mac
`Motif - iOS Mac Mode.md` runs these same prompts locally — no GitHub, no CI — via
`scripts/run-ios-prompts-mac.sh`, and overrides the CI parts of each prompt (§4 there).

### Why one prompt per session
A fresh session starts cold and re-reads the plan, which is intended. Several prompts in
one session burns context and quality drops.

### Source-of-truth files
- `Motif - Tech Plan - iOS.md` — the iOS spec; `§N` refs point here.
- `src/` — **the real spec.** The TS model, its tests and the web screens define behaviour.
  When the plan and the TS disagree, the TS wins.
- `README.md` → "The rules, as implemented" — the why behind the rules.
- `db/0001_schema.sql`, `db/0002_games.sql` — table and column names.
- `~/projects/financial-management/iOS/` — the proven no-Mac project shell, fastlane and
  TestFlight pipeline to copy from.

---

## §0 Shared Context (canonical rules — already inlined into each prompt below)

> **Project:** Native iOS app (Swift 6, SwiftUI, iOS 26.1, iPhone portrait) in
> `iOS/Motif/`, a second client of the PWA's Neon database. One SPM dependency, ChessKit,
> imported only by `Model/Board.swift`.
>
> **Non-negotiable rules:**
> 1. **The TS is the spec.** Port `src/` file by file (`runner.ts` → `Runner.swift`), keep
>    public API names and the doc comments' reasoning, keep the constants identical. Do not
>    redesign a rule.
> 2. **Port the tests with the code.** Every TS test file in scope becomes an XCTest file in
>    `MotifTests/`. A slice is not done while a ported test fails.
> 3. **Byte-identical where both clients write**: `contentKey`, written PGN, generated FENs.
>    Checked against generated fixtures (§13.2), never hand-edited.
> 4. **Only `Board.swift` knows chess.** Nothing else imports ChessKit. The runner never
>    asks whether a move is legal; the board only submits legal moves.
> 5. **Never show tags, comments or motif while solving.**
> 6. **Times are `Int64` epoch ms**; ISO-8601 only at the Rest boundary.
> 7. **Synchronized folders**: new files under `Motif/`, `MotifTests/`, `MotifUITests/` need
>    no project-file edit. Don't hand-add file references to `project.pbxproj`.
>
> **Done = `ios-ci` green on the PR + ported tests pass + matches cited §§ + scope not
> exceeded.**

---

> **Per-prompt template:** **Run** = the line you paste. **Read first** = what Claude opens.
> **Build** = files to create. **Rules in play** = the inlined non-negotiables for this
> slice. **Out of scope** = leave for later. **Done when** = acceptance checks.

---

# Phase 1 — Foundation

## P01 — Project shell, CI and TestFlight pipeline

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P01**, and
> `Motif - Tech Plan - iOS.md` §1, §2, §3, §14. Create the iOS project shell, the PR check
> and the TestFlight pipeline by adapting Financial Management's, with a placeholder app
> and one passing test. Push the branch and get `ios-ci` green before finishing.

**Read first:** Tech Plan §1, §2, §3, §14; in `~/projects/financial-management`:
`iOS/FinancialManagement/FinancialManagement.xcodeproj/project.pbxproj`, its shared scheme,
`fastlane/*`, `Gemfile`, `.github/workflows/ios-testflight.yml`, `iOS/README-TestFlight.md`,
`iOS/TestFlight-Setup-Progress.md` (the gotchas section especially).

**Build (create):**
- `iOS/Motif/Motif.xcodeproj/project.pbxproj` — three targets (`Motif`, `MotifTests`,
  `MotifUITests`), each on a synchronized folder; iOS 26.1; Swift 6; iPhone portrait;
  bundle IDs per §2.2; `GENERATE_INFOPLIST_FILE` + `Info.plist` with `NeonBaseURL =
  $(NEON_BASE_URL)`. ChessKit package reference (exact version) linked to `Motif`. Fresh
  object IDs.
- `xcshareddata/xcschemes/Motif.xcscheme` — test action runs `MotifTests`.
- `Motif/App/MotifApp.swift`, `AppConfig.swift` (§2.4), a placeholder `RootView`.
- `Motif/Resources/Assets.xcassets` with `AppIcon` (1024×1024 opaque placeholder PNG) and
  `AccentColor`.
- `MotifTests/AppConfigTests.swift` — empty/missing `NeonBaseURL` → `nil`.
- `iOS/Motif/Gemfile`, `fastlane/{Appfile,Matchfile,Fastfile}` — lanes `beta` and `test`
  (§14.2).
- `.github/workflows/ios-ci.yml` and `.github/workflows/ios-testflight.yml` (§14.1).
- `iOS/README-TestFlight.md` — adapted setup guide incl. §14.3.
- `.gitignore` additions: `iOS/**/build/`, `*.xcresult`, `DerivedData/`, `xcuserdata/`.

**Rules in play:** synchronized folders (no per-file pbxproj entries). Reuse Financial
Management's signing fixes verbatim. `NEON_BASE_URL` is required by `beta`, absent in CI
tests.

**Out of scope:** any model or UI code beyond the placeholder.

**Done when:** `ios-ci` is green on the PR (simulator build + `MotifTests`); the TestFlight
workflow is valid YAML and would run once §14.3 is done (it is not expected to succeed
before then); README-TestFlight lists the manual steps.

---

## P02 — Chess rules: `Board.swift` + parity fixtures

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P02**, and
> `Motif - Tech Plan - iOS.md` §0, §4, §6, §13.2. Port `src/model/board.ts` and
> `src/model/move.ts` onto ChessKit, write the fixture exporter and the staleness test, and
> port `board.test.ts`. Decide whether ChessKit can match chess.js; if not, implement the
> fallback. Get `ios-ci` green before finishing.

**Read first:** `src/model/board.ts`, `move.ts`, `board.test.ts`, `games/pgn.ts`
(`playFrom`, its use of `validateFen`, `DEFAULT_POSITION`); Tech Plan §6 and §13.2.

**Build (create):**
- `Motif/Model/Move.swift`, `Motif/Model/Board.swift` — the full `board.ts` API plus
  `playSan`, `validateFen`, `defaultPosition` (§6).
- `scripts/export-ios-fixtures.ts` — writes `board.json` now; structured so P03/P04 add
  `content-keys.json`, `import.json`, `pgn-roundtrip.json`. Add `"export:ios-fixtures"` to
  `package.json`.
- `src/test/iosFixtures.test.ts` — regenerates in memory, fails if committed fixtures are
  stale.
- `iOS/Motif/MotifTests/Fixtures/board.json` (generated).
- `MotifTests/Model/BoardTests.swift` (port of `board.test.ts`) and
  `BoardParityTests.swift` (fixture-driven).

**Rules in play:** only `Board.swift` imports ChessKit. Reproduce chess.js FEN output (ep
square only when capturable), FEN validation, SAN and loose SAN (§6 list). Illegal → `nil`,
never a throw.

**Out of scope:** anything above the board (trie, runner, PGN reader).

**Done when:** `npm test` passes (incl. the staleness test); `BoardTests` and
`BoardParityTests` pass on CI; the PR description states the ChessKit decision and any
chess.js behaviour that needed patching in `Board.swift`.

---

## P03 — Puzzle model: puzzle, trie, runner, session, derive, library, import

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P03**, and
> `Motif - Tech Plan - iOS.md` §0, §4, §5. Port the puzzle model files listed in P03 with
> their tests, and add the content-key and import fixtures. Get `ios-ci` green before
> finishing.

**Read first:** `src/model/{puzzle,trie,runner,session,derive,library}.ts`,
`src/model/import/json.ts`, their tests (`runner`, `missing-piece`, `session`, `derive`,
`library`, `import`), `src/data/backend.ts` types (`Run`, `Attempt`, `Library`), README →
"The rules, as implemented".

**Build (create):**
- `Motif/Model/{Puzzle,Trie,Runner,Session,Derive,Library}.swift`,
  `Motif/Model/Import/ImportJSON.swift`.
- The model-side data types from `backend.ts` needed here (`Run`, `Attempt`,
  `AttemptResult`, `Library`, `RunScope` + `SCOPE_ALL`/`SCOPE_REVIEW`) in
  `Motif/Data/Backend.swift` (types only for now).
- Fixtures `content-keys.json`, `import.json` via the exporter; parity tests for both.
- `MotifTests/Model/{Runner,MissingPiece,Session,Derive,Library,Import}Tests.swift`.

**Rules in play:** constants identical; hint budget per ply; preferred move =
earliest-declared (ordered storage, not `Dictionary` order); `e7e8` fallback only for
queen; `contentKey` byte-identical; injected `rand` with the same Fisher–Yates.

**Out of scope:** games model, networking, UI.

**Done when:** all ported tests and parity tests pass on CI; test counts per file match
the TS files' (note any deliberate difference in the PR).

---

## P04 — Games model: PGN, edit, table, summary, library

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P04**, and
> `Motif - Tech Plan - iOS.md` §0, §4, §5 (games rows), §13.2. Port `src/model/games/*`
> with their tests and add the PGN round-trip fixtures. Get `ios-ci` green before finishing.

**Read first:** `src/model/games/{game,pgn,edit,library,summary,table}.ts` and their tests.

**Build (create):**
- `Motif/Model/Games/{Game,PGN,Edit,GameLibrary,Summary,Table}.swift`.
- Fixture `pgn-roundtrip.json` (cover variations, nested variations, comments before and
  after moves, NAGs, `[%clk]`/`[%eval]`, `[FEN]` starts, black-to-move starts, results,
  multi-game files with a broken game); `PGNParityTests.swift`.
- `MotifTests/Model/Games/{PGN,Edit,GameLibrary,Summary,Table}Tests.swift`.

**Rules in play:** the stored game is its PGN text; the tree is only ever derived from it.
`writePgn` output byte-identical to the TS. Move checking only through `Board.playSan`.

**Out of scope:** networking, UI.

**Done when:** ported + parity tests pass on CI.

---

## P05 — Data layer: auth, PostgREST, backends, cache, outbox, `LibraryStore`

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P05**, and
> `Motif - Tech Plan - iOS.md` §7, §8, §9, §13.1. Port `src/data/*` and `src/useLibrary.ts`
> to Swift with their tests, plus request-shape tests for auth and PostgREST. Get `ios-ci`
> green before finishing.

**Read first:** `src/data/{backend,neon,account,cache,outbox}.ts`, `src/useLibrary.ts`,
`src/data/{backend,outbox}.test.ts`, `scripts/ios-auth-spike.sh`, Tech Plan §7–§9, the
schema files.

**Build (create):**
- `Motif/Data/{Backend,MemoryBackend,Rest,NeonAuth,Account,Cache,Outbox,LibraryStore,Connectivity}.swift`.
- `MotifTests/Support/MockURLProtocol.swift`.
- `MotifTests/Data/{BackendSuite,Outbox,PostgRESTClient,NeonAuth,LibraryStore}Tests.swift`
  — the non-RLS part of `backend.test.ts` run against `MemoryBackend` and `RestBackend`
  over an in-memory `Rest`.

**Rules in play:** no `Origin` header; session = cookie in `HTTPCookieStorage.shared`; JWT
from `set-auth-jwt`/`/token`, refreshed near `exp`, one retry on 401. `Prefer:
return=representation,missing=default`; upsert via `on_conflict` + `resolution=…`. Edits
online-only and flush the outbox first; play goes to the outbox; cache replaced, never
merged; outbox mutations serialized in an actor; atomic file writes.

**Out of scope:** UI (a debug-only view is fine but not required).

**Done when:** all data tests pass on CI; the PR lists which `backend.test.ts` cases were
left web-only (RLS) and why.

---

## P06 — App shell: sign-in, tabs, account, offline states

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P06**, and
> `Motif - Tech Plan - iOS.md` §2.4, §9, §10. Build the app shell on `LibraryStore`:
> sign-in, the three-tab layout with placeholder Puzzles/Games front pages, the Account
> screen, offline and loading states, notices. Get `ios-ci` green before finishing.

**Read first:** `src/ui/{App,SignInScreen,AccountScreen,NavMenu,OfflineNote}.tsx`,
`src/ui/App.css`, Tech Plan §10.

**Build (create):** `App/RootView.swift` (unknown user → blank; signed out → `SignInView`;
no library yet → loading/offline message; else `TabView`), `UI/Account/{SignInView,AccountView}.swift`,
`UI/Shared/{OfflineBanner,NoticeBanner,OfflineNote}.swift`, placeholder
`PuzzlesHomeView`/`GamesHomeView`; launch argument `-MotifMemoryBackend YES` →
`DevAccount` with a clean store.

**Rules in play:** memory backend when `NeonBaseURL` is unset; sign-in vs sign-up toggle as
on the web; sign out returns to Puzzles front page; never flash an empty library.

**Out of scope:** puzzle and game screens.

**Done when:** CI green; a `RootViewTests`/view-model test covers the four root states.

---

# Phase 2 — Puzzles

## P07 — The board

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P07**, and
> `Motif - Tech Plan - iOS.md` §11. Build `BoardInteraction` (pure, fully tested) and
> `BoardView` with tap, drag, promotion and placement pickers, highlights, orientation,
> animation and haptics, plus the piece assets. Get `ios-ci` green before finishing.

**Read first:** `src/ui/Board.tsx`, `Board.css`, `MissingPieceView.tsx` (placement
board), `scripts/e2e-solve.mjs` (the board checks), Tech Plan §11.

**Build (create):** `UI/Board/{BoardInteraction,BoardView,PiecePicker,PieceImages}.swift`;
piece vector assets + `Resources/PIECES.md`; `MotifTests/UI/BoardInteractionTests.swift`;
a SwiftUI preview on a sample position.

**Rules in play:** every interaction resolves to one `Uci` / one placement or nothing; an
illegal or cancelled interaction produces nothing; tap and drag share one path; square
accessibility identifiers `square-<name>`.

**Out of scope:** the puzzle screens using it.

**Done when:** every §11 guarantee has a passing test; CI green.

---

## P08 — Solving: home, collection, session, puzzle views, result card

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P08**, and
> `Motif - Tech Plan - iOS.md` §10, §11. Build the Puzzles front page, the collection
> screen and the solving session (both puzzle kinds, the result card, skip, resume), wired
> to `LibraryStore`. Get `ios-ci` green before finishing.

**Read first:** `src/ui/{PuzzlesSection,PuzzlesHome,CollectionView,SessionScreen,PuzzleView,MissingPieceView}.tsx`,
README → "The rules, as implemented" and "Prior art", Tech Plan §10.

**Build (create):** `UI/Puzzles/{PuzzlesHomeView,CollectionView,SessionView,PuzzleSolveView,MissingPieceSolveView,ResultCard}.swift`
and their view models; the puzzles route enum and redirects.

**Rules in play:** no tags/comment/motif while solving; reply after `REPLY_MS`, result card
only after it animates; a correct move gets no confirmation; every puzzle ends on a card
(comment, motif, every accepted line with yours marked, misses as `2nd  Rd7 → Qxh7+`,
"Missed on move 2 of 3"); Continue is a press; starting a run replaces the scope's run;
skip records a `skipped` attempt.

**Out of scope:** puzzle list/detail, import, collection rename/delete, reset.

**Done when:** view-model tests for the session flow pass; CI green.

---

## P09 — Library management: import, puzzle list & detail, edits

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P09**, and
> `Motif - Tech Plan - iOS.md` §10. Build import (file + paste), the puzzle list and puzzle
> detail, and the online edits: rename/delete collection, edit comment, flag, delete
> puzzle, reset progress. Get `ios-ci` green before finishing.

**Read first:** `src/ui/{ImportScreen,PuzzleListScreen,PuzzleDetailScreen,PuzzlesHome,CollectionView,OfflineNote}.tsx`,
README → "Import", Tech Plan §10.

**Build (create):** `UI/Puzzles/{ImportView,PuzzleListView,PuzzleDetailView}.swift` + view
models; rename/delete/reset actions with confirmation dialogs.

**Rules in play:** edits online-only (disabled with the offline note); a single-collection
file goes into a chosen existing collection or a new one named from the file; an array
file makes one collection each; rejected rows shown with reasons; detail shows comment,
tags, motif, every line replayable, alternative solutions disclosed.

**Out of scope:** games.

**Done when:** view-model tests (import planning, offline-disabled edits) pass; CI green.

---

# Phase 3 — Games

## P10 — Game collections and adding games

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P10**, and
> `Motif - Tech Plan - iOS.md` §10, §12. Build the Games front page, the game collection
> screen (search, select, move/copy/export/delete, reorder) and adding games (paste, files,
> FEN, new board). Get `ios-ci` green before finishing.

**Read first:** `src/ui/games/{GamesSection,GamesHome,GameCollectionScreen,AddGamesScreen,download}.tsx`,
`games.css`, README → "Games", Tech Plan §12.

**Build (create):** `UI/Games/{GamesHomeView,GameCollectionView,AddGamesView}.swift` + view
models; PGN export as a `Transferable` file for `ShareLink`.

**Rules in play:** per-game parse errors reported with the move that broke, the rest still
added; ids set on the device; positions via `GameLibrary`.

**Out of scope:** the game viewer.

**Done when:** view-model tests pass; CI green.

---

## P11 — The game screen

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P11**, and
> `Motif - Tech Plan - iOS.md` §11, §12. Build the game viewer: board, move list with
> variations, stepping, play-in, comments, make main line, delete from here, details,
> orientation, copy/export. Get `ios-ci` green before finishing.

**Read first:** `src/ui/games/{GameScreen,MoveList,Sheet}.tsx`, `games.css`,
`src/model/games/{edit,table}.ts`, Tech Plan §12.

**Build (create):** `UI/Games/{GameView,MoveListView,GameDetailsSheet,CommentSheet}.swift`
+ view model.

**Rules in play:** each change saves straight away as new PGN; offline the game is
read-only; orientation persists per game; clock/eval commands kept but not shown.

**Out of scope:** new features beyond the web's.

**Done when:** view-model tests (play-in extends vs. branches, delete-from-here, promote)
pass; CI green.

---

# Phase 4 — Ship

## P12 — UI tests, icon, polish

**Run:**
> In this repo, read `Motif - iOS Build Prompts.md` → prompt **P12**, and
> `Motif - Tech Plan - iOS.md` §13.3, §13.4. Port the important paths of
> `scripts/e2e-solve.mjs` and `scripts/e2e-games.mjs` to XCUITest on the memory backend,
> add them to `ios-ci`, replace the placeholder icon, and add an iOS section to the README.
> Get `ios-ci` green before finishing.

**Read first:** `scripts/e2e-solve.mjs`, `scripts/e2e-games.mjs`, Tech Plan §13.3.

**Build (create):** `MotifUITests/{SolveFlowTests,GamesFlowTests}.swift`; scheme test
action includes `MotifUITests`; final `AppIcon`; README "iOS app" section (where it lives,
how it's built, the no-Mac pipeline, link to `iOS/README-TestFlight.md`).

**Rules in play:** tests run against `-MotifMemoryBackend YES`; identify squares by
`square-<name>`.

**Out of scope:** App Store submission, account deletion.

**Done when:** UI tests pass in `ios-ci`; README updated.
