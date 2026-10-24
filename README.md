# Motif

Continuous chess puzzle sessions over collections you import yourself. Show a
puzzle, solve it, move to the next one — Duolingo's pacing rather than a
puzzle-of-the-day.

Beside the puzzles, a Games section keeps collections of games — your own,
annotated, with their variations — to read through and add to.

A React PWA, deployable to GitHub Pages, installable to an iPhone home screen.
Your library lives in your account (Neon Postgres), so it is the same on every
device; solving also works offline.

Named for the chess term: a motif is the idea behind a tactic — the pin, the
fork, the deflection, the back rank. It is also, not by accident, the field on
every puzzle in the schema. That field is deliberately never shown while you are
solving, because naming the idea gives the puzzle away.

## Status

The model layer is written and tested — **183 tests, all passing**. It holds
every decision that is easy to get subtly wrong: what counts as solving a
puzzle, how multiple solutions are matched, what a missing-piece puzzle accepts,
when the answer is revealed, where a run has got to, how missed puzzles come
back, how imports dedupe, and how a game's PGN is read and written back with
its variations. The schema's access rules are tested against a
real Postgres in-process.

    npm test              # 183 tests
    npm run check:e2e     # the whole app in a real browser, on the in-memory backend
    npm run check:e2e:games  # the Games section, the same way
    npm run check:sync    # two devices against the real database (see db/README.md)
    npm run check:external -- puzzles.json   # audit a puzzle file against the rules
    npm run dev
    npm run build

Without `VITE_NEON_BASE_URL` (see `.env.example`), `npm run dev` uses an
in-memory stand-in for the database: any email and password signs in, and each
account's library is kept in that browser's localStorage.

## Why a web app

This was scoped as a native iOS app first. It moved to the web for one reason
that outweighed the rest: development happens on WSL2, where there is no Xcode
and no simulator. A native app could be written here but never *run* here — no
build, no screenshot, no way to verify a single tap. As a PWA the whole loop is
local.

The costs are real and accepted: drag feel and haptics are worse than native,
and iOS evicts script-writable storage after ~7 days of disuse for sites that
aren't installed to the home screen. That matters less now the library lives in
the database: the device only keeps a copy to solve from offline, plus the
attempts waiting to upload, and it still asks `navigator.storage.persist()` for
those.

## The rules, as implemented

**Solving.** A puzzle's accepted continuations are a trie, not a list. Lines
sharing a prefix merge into shared nodes, so a puzzle where two moves both win —
or where the winning line branches at move three — needs no special casing. Each
edge carries the opponent's scripted reply, so divergent lines answer correctly.

**Where a line stops.** A solution may end on either side's move. Odd length
ends on yours. Even length ends on the opponent's forced reply — you play the
key move, the answer is played for you, and the puzzle stops there. That is how
you author "and now he *must* take, which is the whole point" without demanding
a follow-up move that isn't the idea. The reply animates first and the result
card comes up after it, so the last move is something you watch rather than
something the card tells you about. Everything downstream is unchanged: comment,
motif, every accepted line, and Continue when you're ready.

**Failing.** Any legal move that is not an accepted continuation marks the
attempt failed, permanently, even if everything after it is right. A puzzle's
status is its latest result, so re-solving cleanly later makes it solved again,
while the failed attempt stays on record and in its mistake count.

Each wrong move is also kept, tagged with the move of the line it was played
for, and the result card shows them in SAN against the move that was wanted:
`2nd  Rd7 → Qxh7+`. On a multi-move puzzle the verdict names where the line
broke — "Missed on move 2 of 3" — because a count alone cannot say whether you
missed the idea or only the follow-up. The number counts your own moves, so
opponent replies sitting between them never shift it.

**Starting over.** *Reset progress* on the Puzzles page deletes every attempt
and run and leaves the library alone — the point is to solve the puzzles again,
not to re-import them. One edge case is accepted: attempts another device made
offline before the reset still upload afterwards, and count.

**Input and fairness.** The model validates moves; it does not know chess. The
UI generates legal moves with chess.js and calls `submit` only for moves legal
on the board. So an illegal drag, a drop off-board, a deselect or a cancelled
promotion never reaches the validator and costs nothing — while a legal move to
the wrong square is a mistake. That distinction falls out of the structure
rather than out of a special case. Tap-to-move and drag both normalize to the
same UCI string, one code path.

**Hints.** Three wrong tries on a ply reveals the expected move, and the reveal
is the earliest-declared solution rather than whatever map iteration yields
first. The budget is per ply, not per puzzle — a long line gives three tries at
each move. Revealing does not end the puzzle; you play the move and continue.

**Retries.** A missed puzzle is re-served once later in the *same* session,
after `RETRY_GAP = 3` others so the answer isn't just echoed back, with at most
`MAX_RETRIES = 10` waiting so a bad run can't build a backlog. Progress is
measured against the original queue length, so retries never make the bar slip
backwards.

**Promotion.** Moves are 5-char UCI (`e7e8q`). Source data that writes a
queening as plain `e7e8` still matches, via a lookup fallback in the trie — the
model has no board and so cannot normalize this at import time. Underpromotions
carry `n`/`r`/`b`, never take that fallback, and correctly fail a line expecting
a queen.

**The missing piece.** A second kind of puzzle, answered by placing a piece
rather than by playing a move: the position is one piece short of the idea, and
the question is which piece and where. The board stops being a move board —
nothing drags, occupied squares do nothing — and a tap on an empty square opens
the same picker a promotion does, with a pawn added and the king left out. The
two acts are separate on purpose: choosing the square commits to nothing, and
cancelling the picker is free, exactly as a cancelled promotion is. Only a
complete guess can be wrong, and the three-tries-then-reveal rule is the same
one, deliberately sharing its constant.

The kind is derived from the data rather than declared: a puzzle with an
`add_piece` is a missing-piece puzzle and one without is not, so the two can
never disagree. The piece is written FEN-style, so its case is its colour —
`Ng6` is a white knight — which matters because the answer is often not the
side to move: in the archetype the position is Black to move and a white knight
mates. Since the puzzle accepts exactly one placement, an authored position
where two different pieces would do marks a correct answer wrong;
`check:external` audits for that specifically.

**Sessions.** A session is a *run*: its queue is fixed when it starts, and
that, with its scope, mode and start time, is all that is stored. Where it has
got to — the current puzzle, retries owed, the progress bar — is worked out
from the attempts made in it (`src/model/derive.ts`), so resuming on another
device is exact and two devices playing one run can never conflict; the worst
case is seeing a puzzle twice. A skip is an attempt too, with result `skipped`:
the puzzle doesn't come back that run and counts as neither solved nor failed.
Puzzles deleted since the run started drop out of its queue. Each collection,
the library-wide draw and review each hold one run; starting another replaces
it.

**Tags and comments.** Both live on the puzzle, and neither is rendered while
solving — they are spoilers. They surface on the result card and in puzzle
detail, alongside a disclosure of any alternative solutions you didn't play.

## Import

A JSON file, chosen or pasted. See `samples/back-rank.json`, and
`samples/missing-piece.json` for the other kind:

    { "collection": "Missing pieces",
      "puzzles": [
        { "id": 187,
          "fen": "6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1",
          "solutions": [],
          "tags": ["missingPiece"],
          "comment": "Add a knight and it's mate",
          "add_piece": "Ng6" } ] }

`id` is the puzzle's number in its source, shown as `#187`; `rating` is
optional. A file may also be an array of such objects — a book's chapters —
and then each becomes a new collection of its own. A single-collection file
goes where you choose: into an existing collection, or a new one named after
the file's `collection` by default.

Each puzzle belongs to exactly one collection; the same position imported into
two collections is two puzzles, with their own progress and comment. Within a
collection, identity is a canonical string of position + accepted solutions
(+ placement) — not a digest, so it cannot collide and stays legible. Move
counters are stripped and solution order normalized. A puzzle listed twice in a
file appears once, and re-importing a file into the same collection updates its
puzzles' tags, comment, rating and number instead of adding them again — the
file wins over a comment edited in the app. Rejected rows come back with
reasons rather than being silently dropped.

## Games

A personal take on Chess.com's game collections, without the sharing and the
community: collections of games, each game one PGN.

- **Adding**: paste PGN or choose `.pgn` files, many games to a file. A game
  that can't be read is reported with the move that broke it, and the rest
  still come in. A FEN on its own, or "New game on the board", starts a game
  with no moves to play into.
- **Reading**: the board, a move list with variations indented under the move
  they replace, arrow keys to step. Clock and eval commands that the big sites
  put in comments are kept in the PGN but not shown.
- **Annotating**: a move played on the board carries the line on at its end,
  or starts a variation anywhere else. Comments on any move, a note on the
  whole game, "Make main line", "Delete from here", and the players, event,
  date and result in Details. Each change saves straight away.
- **The board stays as you flipped it**, per game.
- **Collections**: search by player, event or opening; select games to move,
  copy, export or delete; reorder by moving a game up or down; export the
  whole collection as one PGN file.

The stored game is its PGN text; the tree of moves is only ever derived from
it (`src/model/games/pgn.ts`). chess.js reads PGN too, but drops every
variation, so the movetext is read here and chess.js checks each move. Games
open offline from the device's copy and are read-only there, like every other
edit.

## Data

The database is the source of truth (`db/0001_schema.sql` and
`db/0002_games.sql`, set up as described in `db/README.md`): collections,
puzzles, runs and attempts, game collections and games, each row private to
its account by row-level security. Signing in is required.

- **Edits** — importing, renaming and deleting collections, editing comments,
  deleting puzzles, resetting progress — are written straight to the database,
  and the library is then read back. They need a connection; offline they are
  disabled, with a note saying so.
- **Play** works offline. The device keeps a read-only copy of the library to
  solve from (`src/data/cache.ts`), and starting a run or finishing a puzzle
  goes into an outbox (`src/data/outbox.ts`) that uploads on opening, on
  returning to the foreground, on reconnecting and after each solve. Runs and
  attempts are only ever inserted, so uploading late cannot conflict with
  anything, and uploading twice stores once.
- The copy is replaced, never merged, whenever the server is reached, with the
  outbox laid on top.

## Layout

    src/model/          # pure logic, no React — this is the tested part
      move.ts           # UCI parsing
      puzzle.ts         # puzzle, placement, collection, content key
      trie.ts           # accepted-continuation tree
      runner.ts         # one puzzle: validation, mistakes, hints — both kinds
      board.ts          # the only file that knows the rules of chess
      session.ts        # queue order, retry rules, the library-wide draw
      derive.ts         # status, counts, review set, run progress — from attempts
      library.ts        # reading the library; planning an import
      import/json.ts    # the import format
      games/            # the Games section's model
        pgn.ts          # reading and writing PGN, variations and all
        edit.ts         # playing moves in, comments, headers, variations
        library.ts      # reading game collections; moving, copying, reordering
        summary.ts      # how a game is named, searched and annotated in a list
    src/data/
      backend.ts        # the Backend interface: PostgREST and in-memory
      neon.ts           # Neon's Data API and Neon Auth
      account.ts        # signing in; the dev stand-in when there is no database
      cache.ts          # this device's copy of the library
      outbox.ts         # runs and attempts waiting to upload
    src/useLibrary.ts   # the signed-in library, as the UI sees it
    src/ui/
      App.tsx           # the shell: sign-in, loading, and the menu between sections
      PuzzlesSection.tsx  # the Puzzles section's screens and what they do
      games/            # the Games section: collections, adding, the game viewer
      AccountScreen.tsx # who is signed in, sync state, signing out
      Board.tsx         # moves, promotion, and the placement board
      PuzzleView.tsx    # dispatches on the kind
      MissingPieceView.tsx

## Prior art in this repo family

`../chess-repertoire` is an opening-repertoire trainer with spaced repetition.
Different domain, but its drill loop was tuned against real use and three of its
findings are baked in here: `REPLY_MS = 450` (measured, not guessed), the
retry-gap idea, and the rule that a correct *move* gets no confirmation step —
"being right is the unremarkable case," and a card between every move doubled
how long a line took to walk.

A finished *puzzle* is the exception, and this app departs from the trainer
there. Every puzzle now ends on a card — solved or missed alike — showing the
comment, the motif and every accepted line, with the one you played marked.
The comment is written for the moment the puzzle resolves, and a clean solve is
exactly when there is attention left to read it; flashing it for 700ms meant
the puzzles you understood taught you nothing. Advancing is always a press.
