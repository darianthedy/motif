# Motif — Technical Plan: iOS (Swift / SwiftUI)

> The canonical spec for the native iOS app. `§N` references in
> `Motif - iOS Build Prompts.md` point here.
>
> The iOS app is a **second client** of the same account, not a replacement:
> the PWA stays, both read and write the same Neon database, and a library
> imported on one is the same library on the other.

---

## 0. The one rule: the web app is the spec

The TypeScript in `src/` is not a reference implementation to be loosely
followed — it **is** the specification. It was written to hold every decision
that is easy to get subtly wrong (README → "The rules, as implemented"), and
its 184 tests pin those decisions down. The Swift app ports it; it does not
redesign it.

Concretely:

1. **One Swift file per TS file** in the model and data layers, same name in
   UpperCamelCase (`runner.ts` → `Runner.swift`). A reader holding both should
   be able to walk them side by side.
2. **Doc comments come across.** The comments in `src/model/` explain *why*;
   that reasoning applies to the Swift too. Translate them, trim web-only
   remarks, keep the rest.
3. **Constants are identical**: `ATTEMPTS_BEFORE_HINT = 3`, `REPLY_MS = 450`,
   `RETRY_GAP = 3`, `MAX_RETRIES = 10`, `RECENT_MEMORY = 24`, `CHUNK = 200`,
   `PAGE_SIZE = 1000`.
4. **Every TS test is ported** to XCTest, one test file per TS test file, test
   names kept recognisable. Exception: the PGlite schema tests in
   `src/data/backend.test.ts` that exercise row-level security stay web-only —
   they test the database, not a client (§13.1).
5. **Anything both clients write must be byte-identical** — the puzzle
   `content_key`, written PGN, FENs stored on rows. These are checked against
   fixtures generated from the TS (§13.2), not by eye.
6. **The screens follow the web screens.** Each SwiftUI screen's behaviour —
   what it shows, what it hides (tags, comments and motif are never shown while
   solving), what each button does, what is disabled offline — comes from the
   matching file in `src/ui/`. The *look* is native iOS (§10), the *behaviour*
   is the web's.

When the TS and this document disagree, the TS wins and this document is wrong.

---

## 1. Prerequisites & constraints

- **No Mac.** Development happens on WSL2. Nothing is built or run locally.
  Every build runs on a GitHub-hosted macOS runner (§14). This is the same
  setup as `~/projects/financial-management`, where it is proven end to end.
- **The repo is public**, so GitHub macOS minutes are free.
- **Signing is shared with Financial Management**: Apple team `F73L2977Q8`, the
  `darianthedy/ios-certificates` match repo, the same App Store Connect API key.
  Only the bundle ID, the app record and this repo's secrets are new (§14.3).
- **Verification is CI.** "Builds" means the PR check (`ios-ci.yml`) is green:
  it compiles for the simulator and runs the XCTest suite. A session cannot see
  the app; it relies on the tests, so the tests matter more here than on the web.
- **Out of scope for now**: in-app account deletion (needed only for public App
  Store review, guideline 5.1.1(v) — TestFlight is fine without it), iPad
  layouts, widgets, notifications, Sign in with Apple.

---

## 2. Project setup

### 2.1 Location and project file

```
iOS/
  Motif/
    Motif.xcodeproj/          # synchronized folders — see below
    Motif/                    # app sources
    MotifTests/               # XCTest unit tests
    MotifUITests/             # XCUITest
    Gemfile                   # pins fastlane
    fastlane/{Appfile,Matchfile,Fastfile}
  README-TestFlight.md
```

The project file is **hand-written once and then never edited for new files**:
it uses Xcode 16+ synchronized folders (`PBXFileSystemSynchronizedRootGroup`),
so any `.swift` file placed under `Motif/`, `MotifTests/` or `MotifUITests/` is
compiled into the matching target automatically. Model it on
`~/projects/financial-management/iOS/FinancialManagement/FinancialManagement.xcodeproj/project.pbxproj`
(673 lines, three synchronized groups) — copy its structure, rename targets and
identifiers, generate fresh 24-hex object IDs. **Commit the shared scheme**
(`xcshareddata/xcschemes/Motif.xcscheme`) so CI can find it, with the test
action including both test targets.

No XcodeGen, no CocoaPods.

### 2.2 Targets and settings

| Setting | Value |
|---|---|
| Bundle ID | `com.dthedy.Motif` (tests: `com.dthedy.MotifTests`, `com.dthedy.MotifUITests`) |
| Display name | Motif |
| Deployment target | iOS 26.1 (same as Financial Management; runner is `macos-26`) |
| Swift | 6, language mode 6, strict concurrency complete |
| Devices | iPhone only, portrait only (the PWA manifest is portrait too) |
| Info.plist | `GENERATE_INFOPLIST_FILE = YES` plus a small `Info.plist` for custom keys |
| Version | `MARKETING_VERSION = 0.1.0`; build number set by CI (`CURRENT_PROJECT_VERSION`) |

### 2.3 Dependencies (Swift Package Manager)

Exactly one: **ChessKit** — `https://github.com/chesskit-app/chesskit-swift`,
MIT, pinned to an exact version. It supplies legal-move generation, FEN, SAN
and checkmate detection. It is imported **only** by `Model/Board.swift` (§6).

Everything else — HTTP, JSON, persistence — is Foundation. No Supabase SDK, no
networking library: the PostgREST surface used is small (§8) and a hand-written
client mirrors the TS `Rest` interface exactly.

### 2.4 Configuration

One value, as on the web: the Neon base URL (`VITE_NEON_BASE_URL` there). It is
public by design — RLS is the boundary (`db/README.md` §1) — but, as on the
web, it is supplied at build time rather than committed.

- Info.plist key `NeonBaseURL` = `$(NEON_BASE_URL)`.
- `Config/Base.xcconfig` (the project's base configuration) ends with
  `#include? "Local.xcconfig"`; the git-ignored `Local.xcconfig` may set
  `NEON_BASE_URL` on a Mac (see `Motif - iOS Mac Mode.md` §2.4). CI passes
  `NEON_BASE_URL` as a build setting from the repo secret `VITE_NEON_BASE_URL`
  (the same secret the Pages deploy uses).
- `AppConfig.neonBaseURL: URL?` reads it; empty or missing → `nil`.
- **`nil` means the in-memory dev backend** (§8.4), exactly like the web's
  `usingDevAccount`: any email and password signs in. The PR check and UI tests
  build without the secret and therefore run against it. The TestFlight lane
  **fails the build** if the secret is missing (`ENV.fetch`), as the Pages
  deploy does.

---

## 3. Project structure

```
Motif/
  App/
    MotifApp.swift            # @main; injects LibraryStore; root switch
    AppConfig.swift           # §2.4
    RootView.swift            # signed out / loading / TabView — App.tsx
  Model/                      # pure Swift, no SwiftUI, no networking — the tested part
    Move.swift                # move.ts
    Puzzle.swift              # puzzle.ts
    Trie.swift                # trie.ts
    Runner.swift              # runner.ts — PuzzleRunner, MissingPieceRunner
    Board.swift               # board.ts — the only file that imports ChessKit
    Session.swift             # session.ts
    Derive.swift              # derive.ts
    Library.swift             # library.ts
    Import/ImportJSON.swift   # import/json.ts
    Games/
      Game.swift              # games/game.ts
      PGN.swift               # games/pgn.ts
      Edit.swift              # games/edit.ts
      GameLibrary.swift       # games/library.ts
      Summary.swift           # games/summary.ts
      Table.swift             # games/table.ts
  Data/
    Backend.swift             # backend.ts — Backend protocol, Library, Run, Attempt, row mapping, RestBackend
    MemoryBackend.swift       # backend.ts memoryBackend
    Rest.swift                # Rest protocol + PostgRESTClient (neon.ts neonRest)
    NeonAuth.swift            # neon.ts neonAccount — §7
    Account.swift             # account.ts — Account protocol, DevAccount
    Cache.swift               # cache.ts
    Outbox.swift              # outbox.ts
    LibraryStore.swift        # useLibrary.ts — @Observable @MainActor
    Connectivity.swift        # NWPathMonitor wrapper (navigator.onLine)
  UI/
    Board/                    # §11
      BoardView.swift
      BoardInteraction.swift  # pure state machine, unit-tested
      PiecePicker.swift       # promotion + placement picker
      PieceImages.swift
    Puzzles/                  # PuzzlesSection.tsx and its screens
    Games/                    # games/*.tsx
    Account/                  # SignInScreen.tsx, AccountScreen.tsx
    Shared/                   # OfflineNote, notices, small views
  Resources/
    Assets.xcassets           # AppIcon, piece images (vector PDF/SVG)
MotifTests/
  Fixtures/                   # generated from the TS — §13.2, never hand-edited
  Model/…Tests.swift          # one per TS test file
  Data/…Tests.swift
  UI/BoardInteractionTests.swift
  Support/MockURLProtocol.swift
MotifUITests/
  SolveFlowTests.swift        # scripts/e2e-solve.mjs
  GamesFlowTests.swift        # scripts/e2e-games.mjs
```

---

## 4. Swift conventions

- **Model types are value types**: `struct`/`enum`, `Sendable`, `Hashable`
  where useful, `Codable` where they cross a boundary (cache, outbox, fixtures).
  The two runners are `final class`es, as they are mutable sessions in the TS.
- **Times are `Int64` epoch milliseconds**, as in the TS (`addedAt: number`) —
  not `Date` — so derive/session logic and fixtures compare exactly. Convert to
  `Date` only for display and to ISO-8601 (with fractional seconds) at the
  Rest boundary, as `backend.ts` `iso`/`time` do.
- **`Uci` is a distinct type** (`struct Uci: Hashable, Codable { let text: String }`)
  with `parse(_:) -> Uci?`, mirroring the TS branded string. Never build one
  from an unchecked `String`.
- **TS unions → Swift enums with associated values** (`MoveOutcome`,
  `SyncStatus`, routes). `null`/`undefined` → optionals; keep the TS's
  distinction between "absent" and "empty" where it has one (`cleanComment`).
- **`Map`/`Set` iteration order matters in places** (the hint is "the
  earliest-declared solution rather than whatever map iteration yields first").
  Where the TS relies on insertion order, use arrays or an ordered structure in
  Swift — `Dictionary` order is not insertion order.
- **Sorting**: JS `Array.prototype.sort()` with no comparator compares UTF-16
  code units. For the ASCII strings involved (UCI moves, ids) Swift `<` on
  `String` agrees; `contentKey` relies on this and is fixture-checked.
- **Randomness is injected** (`rand: () -> Double`), as in `session.ts`, so
  tests are deterministic. Ports of tests that pass a seeded `rand` must pass
  the same sequence.
- **Concurrency**: `LibraryStore` and view models are `@Observable @MainActor`;
  `PostgRESTClient`, `NeonAuth`, `Cache`, `Outbox` are `actor`s or `Sendable`
  structs over actors. The model layer is synchronous and isolation-free.

---

## 5. Model port — file by file

Each row: port the TS file, keep its public API (names in lowerCamelCase), port
its tests. "Notes" lists what does not translate mechanically.

| TS | Swift | Tests | Notes |
|---|---|---|---|
| `move.ts` | `Move.swift` | (inside runner/trie tests) | `Uci`, `PromotionPiece`, `parseUci`, `makeMove`, `stripQueenPromotion`. |
| `puzzle.ts` | `Puzzle.swift` | `import`, `missing-piece` | `Placement` parse/text FEN-style case = colour. `normalizeFen`, `contentKey` (**fixture-checked**), `solverSide`, `isMissingPiece`. |
| `trie.ts` | `Trie.swift` | `runner.test.ts` | Trie of accepted continuations; edges carry the scripted reply; `preferredMove` = earliest-declared; the `e7e8` → `e7e8q` lookup fallback in `findEdge`; underpromotions never take it. Children must be stored in declaration order. |
| `runner.ts` | `Runner.swift` | `runner.test.ts` (68), `missing-piece.test.ts` (32) | `PuzzleRunner`, `MissingPieceRunner`, `Miss`, `MoveOutcome`. Hint budget per ply. `revealHint()` is a method because reading it records the hint. |
| `board.ts` | `Board.swift` | `board.test.ts` (11) | The ChessKit adapter — §6. |
| `session.ts` | `Session.swift` | `session.test.ts` | `SessionMode` raw values are the DB strings (`ordered`, `randomInCollection`, `randomGlobal`, `reviewMistakes`). Fisher–Yates exactly as written so seeded tests match. |
| `derive.ts` | `Derive.swift` | `derive.test.ts` (14) | Status/records/review set/stats/`runProgress`. Retries, progress against original queue length, skipped attempts, deleted puzzles dropping out of a queue. |
| `library.ts` | `Library.swift` | `library.test.ts` | `planImport` (dedupe within collection, re-import updates). |
| `import/json.ts` | `Import/ImportJSON.swift` | `import.test.ts` (19) | Single collection or array of collections; rejected rows with reasons; uses `Board.isValidFen` and `firstIllegalMove`. Parse with `JSONSerialization` (the format is loose — numbers or strings for `id`), not `Codable`. |
| `games/game.ts` | `Games/Game.swift` | — | Types only. |
| `games/pgn.ts` | `Games/PGN.swift` | `pgn.test.ts` (18) | The hand-written movetext reader (variations, comments, NAGs, clock/eval commands kept but hidden) and writer. **Writer output is fixture-checked** — a game edited on iOS and then on the web must not churn. Move checking goes through `Board.playSan` (§6). |
| `games/edit.ts` | `Games/Edit.swift` | `edit.test.ts` (13) | `MovePath`, play-in, delete from here, promote variation, comments, headers. Pure functions returning new values. |
| `games/library.ts` | `Games/GameLibrary.swift` | `games/library.test.ts` | Append/copy/move/shift positions. |
| `games/summary.ts` | `Games/Summary.swift` | `summary.test.ts` | Title, subtitle, search, `displayComment` (strips `[%clk]`/`[%eval]`). |
| `games/table.ts` | `Games/Table.swift` | `table.test.ts` | The move-list layout (cells, variation rows) that `MoveList.tsx` renders. |

---

## 6. Chess rules — `Board.swift`

`board.ts` is "the only file that knows the rules of chess", and that boundary
is what makes *an illegal drag is free, a legal wrong move is a mistake* a
structural fact. `Board.swift` keeps it: it is the **only** file that imports
ChessKit, and its API is `board.ts`'s, working on FEN strings and `Uci`:

`squares`, `isValidFen`, `isCheckmate`, `turnOf`, `targetsFrom(fen, from) ->
[String: Target]` (promotions collapsed into one target), `isLegal`, `applyUci
-> String?`, `sanFor -> String?`, `needsPromotion`, `firstIllegalMove`,
`pieceAt`, `withPiece -> String?`, `emptySquares`, `matingPlacements`,
`replayLine`, plus what `pgn.ts` gets from chess.js directly:
`playSan(fen, san) -> (san, uci, fenAfter)?` (loose SAN, as `strict: false`),
`validateFen`, `defaultPosition`.

**chess.js behaviour that must be reproduced**, because the stored data and
fixtures depend on it:

1. **FEN output**: chess.js v1 writes the en-passant square only when an
   en-passant capture is actually legal. Match it.
2. **FEN validation** (`isValidFen`, `withPiece`'s "loading it is the check"):
   chess.js rejects wrong field counts, bad ranks, missing/extra kings, pawns
   on the first/last rank, the side *not* to move being in check, and
   inconsistent castling/en-passant fields. If ChessKit is laxer, add the
   missing checks in `Board.swift`.
3. **SAN**: disambiguation (file, then rank, then both), `+`/`#`, `=Q`, `O-O`.
4. **Loose SAN input** (`strict: false`): accepts e.g. `Nf3`, `ng1f3`-style
   long algebraic, missing `+`/`#`, `0-0`. `pgn.test.ts` covers the cases used.
5. **`put`** onto an occupied square is refused by `withPiece` before it gets
   that far; a pawn on rank 1/8 likewise.

**Risk and fallback.** If ChessKit cannot be made to match these within
`Board.swift` (P02 decides), replace it with a hand-written move generator in
`Model/Chess/` (0x88 or mailbox; ~800 lines) behind the same `Board` API. The
rest of the app cannot tell, which is the point of the boundary.

---

## 7. Authentication — Neon Auth (Better Auth) over URLSession

Verified by `scripts/ios-auth-spike.sh` against production (2026-10-25):

| Step | Request | Result |
|---|---|---|
| Sign in | `POST {auth}/sign-in/email` `{email, password}` — **no `Origin` header** | 200, sets the session cookie |
| Session | `GET {auth}/get-session` with the cookie | 200, `{user, session}`, JWT in the **`set-auth-jwt`** response header |
| Token | `GET {auth}/token` with the cookie | 200, `{token}` |
| Data API | `GET {rest}/collections?select=id&limit=1`, `Authorization: Bearer <jwt>` | 200, rows limited by RLS |

No `set-auth-token` (bearer plugin) header is issued: **the session is the
cookie.** An `Origin` of `exp://…` was refused (`INVALID_ORIGIN`), so the client
must never set one; URLSession doesn't by default.

URLs derive from the base URL exactly as `@neondatabase/neon-js` does — insert
a label after the first hostname label:

- auth: `https://<ep>.neonauth.<rest-of-host>/<db>/auth`
- rest: `https://<ep>.apirest.<rest-of-host>/<db>/rest/v1`

`NeonAuth` (an `actor`, implementing `Account`):

- `URLSession` with a configuration whose `httpCookieStorage` is
  `HTTPCookieStorage.shared` and `httpShouldSetCookies = true`: the session
  cookie persists across launches the way Safari's would. No Keychain needed
  for the session itself.
- `signIn(email, password)`, `signUp(email, password)` — sign-up sends
  `name` = the local part of the email, as `neon.ts` does. Error bodies are
  `{message, code}`; surface `message`.
- `currentUser() -> User?` — `GET /get-session`; `user.id` + `user.email`;
  also captures `set-auth-jwt`.
- `signOut()` — `POST /sign-out`, then clear cookies for the auth host and the
  cached JWT.
- `jwt() -> String` — cached; decode the payload's `exp` and refresh via
  `GET /token` (or `get-session`'s header) when within 60 s of expiry. A 401
  from the Data API refreshes once and retries once.

Offline, `currentUser()` cannot be asked; `LibraryStore` falls back to the
**remembered user** in `UserDefaults` (`motif:user`), exactly as
`useLibrary.ts` does, so the cached library still opens.

---

## 8. Data API client and `Backend`

### 8.1 `Rest` protocol

The Swift `Rest` mirrors `backend.ts`'s `Rest` interface — `select(table,
filters)`, `insert(table, rows, upsert?)`, `update(table, patch, filters)`,
`delete(table, filters)` — with `Row = [String: JSONValue]` and
`Filter = .eq(column, value) | .in(column, [value]) | .lt(column, value)`.
`RestBackend` is written against the protocol, so its tests run on a
`MockURLProtocol` and on an in-memory `Rest` alike.

### 8.2 `PostgRESTClient` — what `postgrest-js` sends, by hand

- Base `{rest}/{table}`, header `Authorization: Bearer <jwt>`, `Accept` and
  `Content-Type: application/json`.
- Filters as query params: `col=eq.<v>`, `col=in.(<v1>,<v2>)` (quote values
  containing `,`, `(`, `)` or `"` with PostgREST quoting), `col=lt.<v>`.
- **select**: `select=*`, `order=id.asc`, `offset`/`limit` pages of
  `PAGE_SIZE = 1000` until a short page — `neonRest.select`.
- **insert**: `POST`, body = JSON array, `Prefer: return=representation,missing=default`
  (`defaultToNull: false` — an omitted column takes its default; that is how a
  new puzzle gets its id). With upsert: `on_conflict=<cols>` and
  `resolution=merge-duplicates` or `resolution=ignore-duplicates` added to
  `Prefer`. Returns the stored rows.
- **update**: `PATCH` with filters, body = patch object.
- **delete**: `DELETE` with filters.
- Non-2xx → throw with the PostgREST `message`.

Request shapes are pinned by tests (`MockURLProtocol`, as Financial
Management's tests do).

### 8.3 `RestBackend`

A line-for-line port of `restBackend` in `backend.ts`: row mapping
(`puzzleFrom`, `puzzleRow`, `attemptRow`, `gameFrom`), `CHUNK = 200`,
`distinctPuzzles` (last wins), `saveRun` (delete older in scope, then insert
`ignore-duplicates` on `(user_id, scope)`), `recordAttempts` (drop attempts on
puzzles that no longer exist, clear `run_id` for runs that no longer exist),
`resetProgress` filtered by `user_id`, `placeGames` one row at a time.

### 8.4 `MemoryBackend` and `DevAccount`

Port `memoryBackend` and `devAccount`. Same rules as `RestBackend` — the shared
backend suite from `backend.test.ts` (the parts that are not RLS) runs against
both. `DevAccount` persists the user and library to `UserDefaults`/a JSON file
so a dev build survives relaunch, as the web one survives a reload. UI tests
launch with `-MotifMemoryBackend YES` and a clean store.

### 8.5 Schema

`db/0001_schema.sql` and `db/0002_games.sql` are the source of truth for table
and column names. Nothing on iOS changes the schema.

---

## 9. Offline, cache, outbox, `LibraryStore`

A port of `useLibrary.ts`, `cache.ts` and `outbox.ts`. Same semantics:

- **The database is the source of truth.** Edits are online-only, written
  straight to it, then the whole library is read back.
- **Play works offline.** Starting a run and finishing a puzzle go to the
  **outbox**, which uploads on launch, on returning to the foreground
  (`scenePhase == .active`), on reconnecting, and after each solve. Runs are
  uploaded before attempts. One upload at a time; a second request waits for
  the first.
- **The cache is replaced, never merged**, whenever the server is reached, and
  the outbox is laid on top (`overlay`).
- Writing an edit **flushes the outbox first**, so a reset or delete isn't
  followed by play recorded before it.

Storage (replacing IndexedDB):

- `Application Support/Motif/<userId>/library.json` and `outbox.json`, written
  with `.atomic`. Excluded from nothing — Application Support is backed up and
  not evicted, which is the fix for the PWA's 7-day eviction (there is no
  `navigator.storage.persist()` analogue to call).
- The outbox is the one thing that exists nowhere else: every mutation is
  read-modify-write inside the `Outbox` actor, so a flush and an add cannot
  interleave (the TS uses `idb-keyval`'s `update` for the same reason).

`Connectivity` wraps `NWPathMonitor` (`path.status == .satisfied`) as
`online: Bool`. `LibraryStore` exposes what the hook returns: `user`,
`library`, `loaded`, `online`, `status`, `pending`, `write`, `startRun`,
`recordAttempt`, `signIn`, `signOut`.

---

## 10. Navigation & screens

`App.tsx` + `NavMenu.tsx` → a `TabView` with three tabs: **Puzzles**,
**Games**, **Account**. Each tab owns a `NavigationStack` whose path is a typed
route enum ported from `PuzzlesRoute` / `GamesRoute`:

| Web route | iOS screen | Web file |
|---|---|---|
| puzzles `home` | `PuzzlesHomeView` | `PuzzlesHome.tsx` |
| `collection` | `CollectionView` | `CollectionView.tsx` |
| `import` | `ImportView` (sheet) | `ImportScreen.tsx` |
| `puzzles` | `PuzzleListView` | `PuzzleListScreen.tsx` |
| `puzzle` | `PuzzleDetailView` | `PuzzleDetailScreen.tsx` |
| `session` | `SessionView` (full-screen cover; hides the tab bar) | `SessionScreen.tsx`, `PuzzleView.tsx`, `MissingPieceView.tsx` |
| games `home` | `GamesHomeView` | `games/GamesHome.tsx` |
| `collection` | `GameCollectionView` | `games/GameCollectionScreen.tsx` |
| `add` | `AddGamesView` (sheet) | `games/AddGamesScreen.tsx` |
| `game` | `GameView` | `games/GameScreen.tsx`, `MoveList.tsx`, `Sheet.tsx` |
| — | `SignInView`, `AccountView` | `SignInScreen.tsx`, `AccountScreen.tsx` |

Rules carried over from `App.tsx` / the sections:

- **Redirects**: a screen whose collection/puzzle/game has gone (deleted here or
  on another device) pops back to where the web's `Redirect` sends it.
- **Offline**: an "Offline · N to upload" note on the front screens; edit
  controls disabled with the `OfflineNote` text; play still works.
- **Notices**: an edit's result ("That didn't save: …") as a dismissable banner.
- **Loading**: never flash an empty library over an existing one; the
  "offline, no copy yet" message when there is no cache.
- **Sign out** returns everyone to the Puzzles front page.

Native, not web-imitating: system fonts, `List`/`Form` where the web has lists
and forms, `.confirmationDialog` for destructive actions, `.sheet` with
detents for the web's `Sheet`, `ShareLink` for exports, `.fileImporter` for
files, `.swipeActions` where the web has row buttons. Dark-first palette from
the web (`theme_color #16171d`), honouring light mode.

---

## 11. The board

`Board.tsx` + `Board.css` → `UI/Board/`. Two parts:

**`BoardInteraction`** — a pure, unit-tested state machine (no SwiftUI) that
turns taps and drags into at most one `Uci` or one placement. It owns
selection, legal targets (from `Board.targetsFrom`), the pending promotion and
the pending placement. Its guarantees are the e2e invariants and get tests:

- tap-to-move and drag produce the same `Uci` — one code path;
- a drop off the board, an illegal drop, a deselect, a cancelled promotion or
  a cancelled placement **produce nothing** (and so cost nothing);
- a legal move to the wrong square **does** produce a move (the runner decides);
- promotion: one target per promotion square, then the picker (`q r b n`);
- placement mode (missing piece): nothing drags, occupied squares do nothing,
  an empty square opens the picker (`q r b n p`, no king);
- tapping another own piece reselects instead of moving.

**`BoardView`** — SwiftUI rendering: 8×8 grid sized to the width, orientation
(`w`/`b` at the bottom), coordinates, last-move and selected highlights, dot
for a quiet target and ring for a capture (`Board.tsx` styles), the hint
highlight, a drag layer (`DragGesture` with the piece following the finger,
lifted and slightly enlarged), and move animation (`matchedGeometryEffect` or
animated offsets). The opponent's reply is played after `REPLY_MS = 450`, and
the result card appears only after the reply has animated (README → "Where a
line stops").

**Pieces**: vector assets in `Assets.xcassets` (one set, preserve vector
data), taken from the set the web uses (`react-chessboard`, MIT) so the two
clients look alike. Record the set's origin and licence in
`Resources/PIECES.md`.

**Haptics** (`.sensoryFeedback`): selection on pick-up, impact on a move,
error on a wrong move, success on a solve. This is the main thing the native
app is for — keep it subtle.

---

## 12. Games

Port `games/*.tsx`. Notes:

- **Move list** (`MoveList.tsx` over `Table.swift`): main line in two columns,
  variations indented under the move they replace, the current move
  highlighted and scrolled into view; long-press a move for its actions
  (comment, make main line, delete from here) — the web uses a 500 ms hold.
- **Stepping**: back/forward buttons; swipe on the board optional. Hardware
  keyboard arrows via `.onKeyPress` (the web's arrow keys).
- **Play-in**: a move on the board extends the line at its end or starts a
  variation elsewhere (`Edit.playMove`). Each change saves straight away
  (`updateGame` with the new PGN); offline, the game is read-only.
- **Orientation** persists per game (`orientation` column).
- **Details**: players, event, date, result headers (`setHeaders`), game note.
- **Collection**: search (`matchesSearch`), multi-select to move/copy/export/
  delete, move up/down (`shiftGame`), export the collection as one `.pgn` via
  `ShareLink`; copy PGN to the clipboard (`UIPasteboard`).
- **Add games**: paste PGN, `.fileImporter` for one or more `.pgn` files, a FEN
  on its own, or "New game on the board"; per-game parse errors reported with
  the move that broke, the rest still added.

---

## 13. Testing

### 13.1 Unit tests (XCTest, `MotifTests`)

Port every file in `src/**/*.test.ts` except the RLS/schema parts of
`backend.test.ts` (which need Postgres and test the database, so they stay in
`npm test`). The shared backend behaviour suite runs against `MemoryBackend`
and against `RestBackend` over an in-memory `Rest`. Add:

- `PostgRESTClientTests` — request shapes (§8.2) via `MockURLProtocol`;
- `NeonAuthTests` — cookie handling, `set-auth-jwt` capture, JWT refresh,
  error mapping, no `Origin` header, via `MockURLProtocol`;
- `BoardInteractionTests` — §11's guarantees;
- `LibraryStoreTests` — offline open from cache, outbox flush ordering, edit
  flushes first, cache replaced not merged.

### 13.2 Parity fixtures

`scripts/export-ios-fixtures.ts` (run with `tsx`) uses the real TS model to
write JSON into `iOS/Motif/MotifTests/Fixtures/`:

- `content-keys.json` — puzzles (both kinds, reordered solutions, move
  counters) → `contentKey`;
- `pgn-roundtrip.json` — PGN inputs (variations, comments, NAGs, clock/eval,
  FEN start, odd spacing) → parsed tree summary and `writePgn` output;
- `board.json` — FENs → `isValidFen`, `targetsFrom`, `sanFor`/`applyUci` for
  listed moves, `withPiece`, `isCheckmate`;
- `import.json` — import files (incl. `samples/*.json`) → `importJson` result.

XCTest asserts the Swift output equals the fixture exactly. A vitest test
(`src/test/iosFixtures.test.ts`) regenerates them in memory and fails if the
committed files are stale, so a TS rule change cannot silently diverge from
iOS.

### 13.3 UI tests (XCUITest, `MotifUITests`)

Ports of the important paths in `scripts/e2e-solve.mjs` and
`scripts/e2e-games.mjs`, against the memory backend
(`-MotifMemoryBackend YES`), on an iPhone simulator: sign in, import a sample
by paste, solve a puzzle by tap and by drag, a wrong move then the hint, a
promotion, a cancelled promotion costing nothing, a missing-piece puzzle, the
result card, skip; add a PGN game, step through it, play a variation, comment,
export. Elements get `accessibilityIdentifier`s; squares are identified by
name (`square-e4`).

### 13.4 CI gates

- `ios-ci.yml` on every PR touching `iOS/**`: build for simulator + run
  `MotifTests` (+ `MotifUITests` from P12). Required before merge.
- `ios-testflight.yml` on push to `main` touching `iOS/**`: sign, build,
  upload.
- `npm test` keeps running in the Pages deploy, including the fixture
  staleness check.

---

## 14. Build & deployment

### 14.1 Workflows

**`.github/workflows/ios-ci.yml`** — `pull_request` and `workflow_dispatch`,
paths `iOS/**`, `src/model/**`, `scripts/export-ios-fixtures.ts`, the workflow
itself. `runs-on: macos-26`, `maxim-lobanov/setup-xcode@v1` latest-stable, then
`bundle exec fastlane test` (or `xcodebuild test -scheme Motif -destination
'platform=iOS Simulator,name=iPhone 17'` — pick an available simulator with
`xcrun simctl list` in the step if the name changes). Uploads the
`.xcresult` on failure.

**`.github/workflows/ios-testflight.yml`** — copy Financial Management's,
retargeted: working directory `iOS/Motif`, push to `main` on `iOS/**`
(excluding `*.md`) + manual run, `concurrency: ios-testflight`, secrets below,
`BUILD_NUMBER: ${{ github.run_number }}`, `MATCH_CREATE_CERTS` variable for the
first run.

### 14.2 fastlane

Copy `~/projects/financial-management/iOS/FinancialManagement/fastlane/` and
`Gemfile`, with `XCODEPROJ = "Motif.xcodeproj"`, `SCHEME = "Motif"`,
`APP_IDENTIFIER = "com.dthedy.Motif"`, `TEAM_ID = "F73L2977Q8"`. Keep every
fix recorded in its `TestFlight-Setup-Progress.md` gotchas: `setup_ci` +
`MATCH_CREATE_CERTS`, `update_code_signing_settings` scoped to the app target,
`CODE_SIGN_IDENTITY = Apple Distribution`, a 1024×1024 opaque app icon. Pass
`NEON_BASE_URL=#{ENV.fetch("NEON_BASE_URL").shellescape}` in `xcargs`. Lanes:
`beta` (match → build → upload), `test` (simulator tests, no signing).

### 14.3 One-time manual setup (browser only)

1. developer.apple.com → Identifiers → **+** → App ID `com.dthedy.Motif`.
2. App Store Connect → **New App** with that bundle ID (name "Motif" may be
   taken — App Store names are global; the on-device name is unaffected).
3. This repo → Settings → Secrets → Actions: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_CONTENT`, `MATCH_GIT_URL`, `MATCH_PASSWORD`,
   `MATCH_GIT_BASIC_AUTHORIZATION` — **the same values as Financial
   Management's**; `VITE_NEON_BASE_URL` already exists.
4. Variable `MATCH_CREATE_CERTS=true` for the first TestFlight run only — match
   needs to create a profile for the new bundle ID (the distribution cert is
   reused). Delete it after the first green run.
5. TestFlight → add yourself as an internal tester.

`iOS/README-TestFlight.md` carries these steps (adapted from Financial
Management's).

### 14.4 The build-prompts driver

`scripts/run-ios-prompts.sh` — Financial Management's driver, adapted: doc
`Motif - iOS Build Prompts.md`, prompts `P01…P12`, and one change: **it waits
for `ios-ci` on the PR before merging** (a red PR gets a fix session on the
same branch), then waits for TestFlight on `main` as before. TestFlight waits
are skipped until the manual setup (§14.3) is done (`SKIP_TESTFLIGHT=1`).
