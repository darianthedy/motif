# Motif

Continuous chess puzzle sessions over collections you import yourself. Show a
puzzle, solve it, move to the next one — Duolingo's pacing rather than a
puzzle-of-the-day.

A React PWA, deployable to GitHub Pages, installable to an iPhone home screen.

Named for the chess term: a motif is the idea behind a tactic — the pin, the
fork, the deflection, the back rank. It is also, not by accident, the field on
every puzzle in the schema. That field is deliberately never shown while you are
solving, because naming the idea gives the puzzle away.

## Status

The model layer is written and tested — **146 tests, all passing**. It holds
every decision that is easy to get subtly wrong: what counts as solving a
puzzle, how multiple solutions are matched, what a missing-piece puzzle accepts,
when the answer is revealed, how a session resumes, how missed puzzles come
back, and how imports dedupe.

    npm test              # 146 tests, ~140ms
    npm run check:e2e     # the whole app in a real browser
    npm run check:external puzzles.json   # audit a puzzle file against the rules
    npm run dev
    npm run build

## Why a web app

This was scoped as a native iOS app first. It moved to the web for one reason
that outweighed the rest: development happens on WSL2, where there is no Xcode
and no simulator. A native app could be written here but never *run* here — no
build, no screenshot, no way to verify a single tap. As a PWA the whole loop is
local.

The costs are real and accepted: drag feel and haptics are worse than native,
and iOS evicts script-writable storage after ~7 days of disuse for sites that
aren't installed to the home screen. Mitigations: request
`navigator.storage.persist()`, and ship progress export/import early. Puzzles
can always be re-imported; solve history cannot.

## The rules, as implemented

**Solving.** A puzzle's accepted continuations are a trie, not a list. Lines
sharing a prefix merge into shared nodes, so a puzzle where two moves both win —
or where the winning line branches at move three — needs no special casing. Each
edge carries the opponent's scripted reply, so divergent lines answer correctly.

**Failing.** Any legal move that is not an accepted continuation marks the run
failed, permanently, even if everything after it is right. `mistakes` never
resets. Re-solving cleanly later flips the stored status to solved while keeping
the miss on record.

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

**Retries.** A missed puzzle is re-served later in the *same* session, after
`RETRY_GAP = 3` others so the answer isn't just echoed back, capped at
`MAX_RETRIES = 10` so a bad run can't build a backlog. Progress is measured
against the original queue length, so retries never make the bar slip backwards.

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

**Sessions.** The queue is materialized up front, not regenerated from a seed.
Resume is exact and no-repeats-within-a-session is free. A collection edited
between sessions is handled by `reconcile`, which drops dead puzzles while
keeping the cursor in place.

**Tags and comments.** Both live on the puzzle, and neither is rendered while
solving — they are spoilers. They surface on the result card and in puzzle
detail, alongside a disclosure of any alternative solutions you didn't play.

## Import

Two front doors, both producing the same `ImportResult`:

- **JSON** — the hand-authored format, see `samples/back-rank.json`, and
  `samples/missing-piece.json` for the other kind:

      { "id": 187,
        "fen": "6rk/6pp/8/1p1b4/p7/3P4/PPP5/1K5R b - - 0 1",
        "solutions": [],
        "tags": ["missingPiece"],
        "comment": "Add a knight and it's mate",
        "add_piece": "Ng6" }

- **Lichess CSV** — the public puzzle dump, with rating/theme/limit filters,
  because the dump is four million rows. Its quirk is handled explicitly: the
  FEN is one ply early and the first move is the opponent's, kept as `setupMove`
  and animated before your clock starts rather than folded into the FEN.

Identity for dedupe is a canonical string of position + accepted solutions — not
a digest, so it cannot collide and stays legible in a store dump. Move counters
are stripped and solution order normalized. Tags, comment, rating and source are
excluded, so re-importing a file with edited metadata updates the existing
puzzle instead of forking it. Rejected rows come back with reasons rather than
being silently dropped.

## Layout

    src/model/          # pure logic, no React — this is the tested part
      move.ts           # UCI parsing
      puzzle.ts         # puzzle, placement, collection, progress, content key
      trie.ts           # accepted-continuation tree
      runner.ts         # one puzzle: validation, mistakes, hints — both kinds
      board.ts          # the only file that knows the rules of chess
      session.ts        # queue, retries, resume, reconcile
      import/           # JSON and Lichess CSV adapters
    src/ui/
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

## Next

1. Board component: tap-to-move and drag, legal-destination dots, promotion sheet.
2. Session screen: progress bar, hint reveal, result card with alternate-solution disclosure.
3. Persistence via `idb-keyval`, plus export/import of progress.
4. Collection management and the import screen.
5. Review-mistakes mode and stats.
6. GitHub Pages deploy.
