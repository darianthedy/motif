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

The model layer is written and tested — **50 tests, all passing**. It holds
every decision that is easy to get subtly wrong: what counts as solving a
puzzle, how multiple solutions are matched, when the answer is revealed, how a
session resumes, how missed puzzles come back, and how imports dedupe.

The UI is a placeholder. The board and session screens are the next piece of
work.

    npm test        # 50 tests, ~130ms
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

**Sessions.** The queue is materialized up front, not regenerated from a seed.
Resume is exact and no-repeats-within-a-session is free. A collection edited
between sessions is handled by `reconcile`, which drops dead puzzles while
keeping the cursor in place.

**Tags and comments.** Both live on the puzzle, and neither is rendered while
solving — they are spoilers. They surface on the result card and in puzzle
detail, alongside a disclosure of any alternative solutions you didn't play.

## Import

Two front doors, both producing the same `ImportResult`:

- **JSON** — the hand-authored format, see `samples/back-rank.json`.
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
      puzzle.ts         # puzzle, collection, progress, content key
      trie.ts           # accepted-continuation tree
      runner.ts         # one puzzle: validation, mistakes, hints
      session.ts        # queue, retries, resume, reconcile
      import/           # JSON and Lichess CSV adapters
    src/ui/             # React (placeholder for now)

## Prior art in this repo family

`../chess-repertoire` is an opening-repertoire trainer with spaced repetition.
Different domain, but its drill loop was tuned against real use and three of its
findings are baked in here: `REPLY_MS = 450` (measured, not guessed), the
retry-gap idea, and the rule that a correct move gets no confirmation step —
"being right is the unremarkable case," and a card between every move doubled
how long a line took to walk. Only a miss should stop the flow.

## Next

1. Board component: tap-to-move and drag, legal-destination dots, promotion sheet.
2. Session screen: progress bar, hint reveal, result card with alternate-solution disclosure.
3. Persistence via `idb-keyval`, plus export/import of progress.
4. Collection management and the import screen.
5. Review-mistakes mode and stats.
6. GitHub Pages deploy.
