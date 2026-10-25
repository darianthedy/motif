# Motif on this Mac

P01 creates the native project shell. Follow `Motif - iOS Build Prompts.md`
in order and apply §4 of `Motif - iOS Mac Mode.md`. These prompts can be
implemented directly in a coding session; the Claude-based driver is optional.

The project has synchronized source folders for `Motif`, `MotifTests`, and
`MotifUITests`. Adding source files inside them needs no project-file edits.
The shared `Motif` scheme runs the unit suite; UI flows are added in P12.

## Open and verify

Open `iOS/Motif/Motif.xcodeproj` in Xcode 26.1 or later. Select the `Motif`
scheme and an iPhone simulator with iOS 26.1 or newer.

From the repository root:

```sh
fnm use
npm ci
scripts/ios-verify.sh
scripts/ios-screenshot.sh p01-dark
APPEARANCE=light scripts/ios-screenshot.sh p01-light
```

`.node-version` selects the installed Node 24.12.0. Without shell integration,
use `fnm exec --using=24.12.0 scripts/ios-verify.sh`.

The simulator scripts select a device by UDID, prefer the selected Xcode SDK's
runtime, and accept `IOS_SIMULATOR_UDID` to select a particular iPhone. Build
products and screenshots are saved in the ignored `build/` directory.

## Configuration

`Config/Base.xcconfig` leaves `NEON_BASE_URL` empty and optionally includes
the ignored `Config/Local.xcconfig`. `AppConfig.neonBaseURL` is `nil` without
a configured endpoint. The app is a placeholder until the later slices port
the backend and screens.

For a real endpoint, create `iOS/Motif/Config/Local.xcconfig`:

```xcconfig
NEON_BASE_URL = https:/$()/example.neon.tech/neondb
```

Simulator builds disable signing. Device builds use automatic signing with
team `F73L2977Q8`; select your account and device in Xcode.

## P01 checkpoint

The project shell passes 192 web tests and 7 simulator configuration tests.
The dark and light placeholder screenshots were inspected. CI, fastlane, and
TestFlight setup remain W1 work, as specified by Mac Mode.

ChessKit is pinned to exactly 0.17.0 and linked to the app target. Its adapter
and parity tests arrive in P02; only `Model/Board.swift` may import ChessKit.
Required read-only package downloads are authorized for this workflow.
GitHub publishing and CI remain disabled.

## P02 checkpoint

`Model/Move.swift` ports the validated UCI value and move helpers.
`Model/Board.swift` ports the board API, including loose SAN playback,
first-illegal-move detection, missing-piece placement and mating audits, and
solution replay. P02 added the three board-facing value types in
`Model/Puzzle.swift`; P03 extends that file with the puzzle model.

**Decision: keep ChessKit 0.17.0.** It supplies ordinary legal moves; no
replacement generator is needed for the verified corpus. The adapter supplies
chess.js-compatible validation, special-move metadata, check/checkmate
detection, and SAN. Compatibility includes:

- Shortened FEN loading, parseInt-style counters, and ECMAScript whitespace.
  The actual web source accepts check on the non-moving side and stale castling
  flags, even though the original plan describes stricter validation.
- Canonical castling flags, revocation on corner movement/capture, and castling
  behavior when a loaded position has stale rights.
- Legal-only en-passant FEN output, including pinned capturers; the web's
  freshly loaded `put` clears EP. Legacy FENs naming a missing EP pawn preserve
  the pawn-restoration behavior observed during web move/SAN generation.
- SAN disambiguation, capture/check/mate suffixes, all four promotion pieces,
  loose long algebraic input, omitted decorations, and zero-spelled castling.
- Uppercase destination queries and the web's empty-query behavior.

Generate the fixture with `npm run export:ios-fixtures` under Node 24.
`src/test/iosFixtures.test.ts` regenerates it in memory and fails on any stale
committed bytes. Extend `generateFixtures()` for P03/P04; expected values must
continue to come from the TypeScript implementation.

Verification passes 193 web tests and 31 simulator tests: the 11 original board
tests, 9 fixture test groups, 4 UCI boundary tests, and 7 configuration tests.
The fixture covers 62 positions, 27 invalid FENs, 16 UCI parser inputs, 1,601
move queries, and 2,331 SAN inputs, including a deterministic move walk.

## P03 checkpoint

The puzzle model is ported: puzzle identity and placement notation, ordered
solution tries, both runners, per-ply hints, seeded queue building, records,
review/stats, retry progress, library ordering/resumption, import planning, and
JSON import validation. `Data/Backend.swift` contains only the puzzle-side
value types needed here. Games arrive in P04 and backend behavior in P05.
Timestamps use `Int64` epoch milliseconds.

Every current TypeScript case is ported one-for-one: runner 27, missing-piece
21, session 4, derive 14, library 2, import 18. These are the actual source
counts; several counts printed in the original plan are outdated. Six extra
parity groups compare shared outputs and otherwise untested library helpers.

The exporter now generates `content-keys.json`, `import.json`, and
`puzzle-model.json` alongside the unchanged board fixture. They cover 15
content keys (compared as UTF-8 bytes), 20 placement strings, 18 import
payloads, 20 seeded session cases, six runner traces, and library/derive
outputs. They check author order, defence isolation, queen-only fallback,
source-number formatting, metadata filtering, dedupe order, file-wide
rejection indices, and deterministic retry/resume behavior.

One deliberate platform difference: invalid JSON retains rejection index
`-1` and the exact `Not valid JSON: ` prefix, followed by Foundation's parser
diagnostic instead of V8's. Other rejection reasons match verbatim. This
diagnostic is displayed to the user and is never stored as puzzle identity.

Verification passes 193 web tests and 123 simulator tests. The web build and
lint pass; the existing Vite chunk-size warning remains. The fixture-staleness
test was also verified to reject modified `content-keys.json`, then the file
was restored byte-for-byte. No UI changed in this slice.

## P04 checkpoint

The games model is ported: stored game/collection/placement types, PGN reading
and writing, navigation and immutable edits, collection placement/reordering,
game titles/search/comment display, and the move table. `Library` now includes
game collections and games. The stored game remains its PGN string; the tree
is derived, and all move checking goes through `Board.playSan`.

All 48 current TypeScript tests are ported one-for-one: PGN 17, edit 13, game
library 5, summary 5, table 8. The plan's PGN test count is outdated.
Six extra parity groups compare complete parsed trees, exact error messages,
UTF-8 writer bytes, header-only reads, move-table rows/paths, immutable edit
traces, summaries/search, comment display, and collection ordering/movement.

`pgn-roundtrip.json` is generated from the real TypeScript model and covers
86 payloads, three edit sequences with 19 steps, and three deterministic
60-ply walks. Coverage includes nested variations, comments before/after
moves, every supported annotation symbol and suffix, unknown numeric NAGs,
clock/eval commands, escaped and custom headers, FEN/Black-to-move starts,
results, malformed syntax, and a multi-game file with a broken middle game.

Headers use explicit ordered storage so updates retain their original place
and extra headers do not churn. The writer orders the seven roster headers
first, mirrors JavaScript's numeric header-key order, and counts UTF-16 units
for wrapping, including emoji comments. Header order is also explicit in the
fixture because Swift's keyed JSON decoder does not retain object order.
Parsed trees are never used as the cache or persistence representation.

Verification passes 193 web tests and 177 simulator tests. The web build and
lint pass, with the existing Vite chunk-size warning. The staleness guard was
verified to reject modified `pgn-roundtrip.json`, then the file was restored
byte-for-byte. Previous phase fixtures remain unchanged. No UI or networking
changed in this slice; P05 is the data layer.

## P05 checkpoint — data layer

The native account, cookie/JWT auth, PostgREST client, durable dev backend,
cache, outbox and observable library store are implemented. The 20 shared
backend cases run against both MemoryBackend and RestBackend over MemoryRest.
The three source outbox cases are ported; additional tests cover atomic
concurrent additions, serialized uploads, failed retries, offline launch,
cache replacement, request shapes, pagination, chunking and cookie/JWT refresh.

Verification: 193 web tests and 223 native tests passed. Four database access
rules remain web-only: account isolation, foreign-account references,
user_id spoofing, and immutable-column grants. They require PostgreSQL RLS and
schema privileges; a native in-memory fake cannot verify those protections.
No live account or configured endpoint was used. GitHub publishing and CI
remain disabled.

## P06 checkpoint — app shell

Sign-in/sign-up, three native tabs, account/sync status, offline/loading
states and dismissible notices are wired to LibraryStore. Sign-out resets the
selected section. Debug-only clean memory launches and bundled JSON sample
seeding support screenshot routes. Normal launches use the durable dev account
unless NeonBaseURL is configured.

Verification: 193 web tests and 225 native tests passed. All four shell screens
were captured and inspected in dark and light appearance under
`build/screenshots/P06-*.png`; no clipped text or overlapping controls found.

## P07 checkpoint — board

BoardInteraction resolves taps and drags through one legal-move path, defers
promotion/placement to a cancellable picker, and clears in-flight state for new
positions. Nine tests cover every §11 interaction guarantee. BoardView adds
coordinates, target dots/capture rings, selection/last/hint highlights, a lifted
drag layer, 150 ms motion and subtle selection/move/error haptics. Every square
has the required `square-<name>` identifier. The twelve preserved SVG assets
come from the installed react-chessboard package; licence is in PIECES.md.

Verification: 193 web and 234 native tests passed. Dark and light board
screenshots were inspected: 64 square cells, crisp vector pieces, correct
orientation and no clipping. Gesture integration is exercised in P12.

## P08 checkpoint — solving

The puzzles front page, collections and full-screen sessions support ordered,
shuffled, global random and review queues, scope replacement, resume, flag,
skip and explicit Continue. SolveModel owns each attempt's board, asked-from
positions and cancellable reply task. Replies wait 450 ms; result disclosure
waits a further 150 ms for motion. Comments, tags and accepted lines appear only
on the result card, with the played line and grouped SAN misses. Missing-piece
attempts reveal the placed answer on completion.

Verification: 193 web and 239 native tests passed. Home, collection, move solve,
missing-piece solve, clean card and failed card were captured and inspected in
both appearances. Session screens hide the tab bar and retain enough room for
the board and card. P12 will exercise gestures and resume through XCUITest.

## P09 checkpoint — puzzle management

JSON file/paste import previews every rejected row and plans single-group
imports into an existing/new collection or chapter files into separate named
collections. Re-import updates content in place. Lists filter by status/flag
without position thumbnails; detail replays each solution and exposes metadata.
Rename, delete, comment, flag and reset use LibraryStore's online edit path;
destructive actions have native confirmations. Deeper screens hide the tab bar.

Verification: 193 web and 244 native tests passed, including import targets,
chapter order, rejection visibility, offline refusal and solution replay.
All five touched screens were captured and inspected in dark/light mode.

## P10 checkpoint — game collections

Games supports collection creation/rename/delete, header search, selection,
move/copy/delete, neighbour reorder, whole/selected PGN export, pasted or
multiple-file PGN import with per-game failures, and validated FEN/new-board
starts. Game ids are assigned locally and GameLibrary supplies positions.
Exports use Transferable file representations and native ShareLink.

Verification: 193 web and 249 native tests passed. The front page, collection
and add form were captured and inspected in both appearances. Screenshot
batches may set `IOS_SCREENSHOT_SKIP_BUILD=1` only after a current passing build;
the script defaults to building and refuses reuse when no app exists. The game
viewer is the immediately following P11 slice.

## P11 checkpoint — game viewer

The fixed board/move-list layout supports paired main-line rows, indented
foldable variations, cursor highlighting/scrolling, next alternatives, stepping
buttons and keyboard arrows. Play-in extends or branches via Edit; comments,
headers, orientation and deletions persist immediately. Save snapshots run in
order and a failed final save restores the stored copy. Offline controls are
read-only. Clock/eval commands remain in PGN and are hidden from display.

Verification: 193 web and 255 native tests passed. Six viewer tests cover
existing moves versus new branches, subtree deletion, promotion, ordered rapid
saves, offline refusal, rollback, and comment-command preservation. Viewer,
variation, comment and details screenshots were inspected in both appearances;
the board and controls fit, and only the move list scrolls.
