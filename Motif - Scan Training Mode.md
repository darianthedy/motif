# Motif — Scan Training Mode (Requirements)

> Darian Thedy, as of 2026-11-16. Source doc:
> https://claude.ai/artifact/BjDma8oLeUdfUGR2dUidtD
>
> The implementation is in `Motif - iOS Scan Training Plan.md`.

## Goal

Train the check-before-moving habit in Motif puzzles, not only finding the best move.

- **Why:** most lost games come from a skipped check, not an unseen tactic. In review he finds the right move almost every time.
- **Success:** quick scan right in 10 s or less on 80% of puzzles, and fewer skipped-check blunders in game reviews.

## Scans

- **Quick scan (every puzzle):** tap what the opponent's last move attacks now, and what it opened or stopped guarding (castling: the rook too). Then call **Flag** or **No flag**.
- **Flag if:** the quick scan found something, you're in check, or you're +3 or more.
- **Full scan (flagged only):** mark targets, then the checks, captures and threats aimed at them.

## Puzzle flow

1. **Last move** plays and stays highlighted. Timer starts.
2. **Quick scan + flag call:** 10 s.
3. **No flag → move:** 5 s.
4. **Flag → targets:** 20 s. Red before orange, own pieces before theirs. Empty squares only for king-zone and fork squares; a king-zone square is coloured like a piece (red when attackers outnumber defenders, orange at 1–1 or 2–2), otherwise a dot.
5. **Flag → checks, captures, threats:** 15 s. Arrows from a piece to a target, both sides, one move deep.
6. **Flag → move + final check:** 10 s. Before it's played: "their checks after this? What does this piece stop guarding?"
7. **Feedback** after each step. The engine grades the move.

Mix in quiet positions with no flag and no tactic at random, with no fixed ratio or pattern, so a flag can never be predicted.

## Puzzle content and answers

Answers are precomputed with python-chess and Stockfish. The phone runs no engine.

- **Sources:** own games one move before a blunder; Lichess puzzles started one move earlier; quiet positions (eval within 0.5).
- **Quick scan:** new attacks from the to-square, lines opened through the from-square, pieces no longer defended.
- **Targets:** from attacker/defender counts. Red = loses material, orange = 1–1. Plus king-zone and fork squares.
- **Checks, captures, threats:** only moves that win material, mate, or must be stopped (null-move for threats). Extra arrows aren't graded.

## Scoring

- **Fail:** wrong move, or "No flag" on a flagged position. Failed puzzles come back sooner.
- **Soft miss:** flagging a quiet position, missed targets or arrows, over the target time.
- **Timing:** recorded only for the first 2 weeks, then hard limits once the median is under target.
- **Stats:** median quick-scan time, flag accuracy, most-missed category, weekly trend, and a summary Caïssa can read.

## Mobile UX (iOS)

Each step gives a tap and a drag one meaning, so there is no mode switch mid-step.

- **Layout:** step label and timer bar on top; full-width board (about 48 pt squares); action buttons, Undo and Done at the bottom.
- **Quick scan:** tap toggles a square highlight; Flag / No flag buttons. Pieces can't be selected.
- **Targets:** tap a piece for red → orange → clear; tap an empty square for a dot; drag to mark several. Haptic on each change.
- **Checks, captures, threats:** drag from a piece to a square to draw an arrow; nothing moves. Arrows are coloured by side automatically. Tap an arrow to delete it.
- **Move:** normal play. The piece stays ghosted until **Play it** or **Take back** on the final-check sheet.
- **Feedback:** green = correct, dashed = missed, grey × = extra, plus a one-line reason.
- **Code:** a `BoardView` mode (`.play`, `.markSquares`, `.markTargets`, `.drawArrows`) routes gestures to annotation callbacks; one Canvas overlay draws tints, rings, dots and arrows; a `ScanSolveModel` beside `SolveModel` owns steps, timers and grading.

## Scope

- **Where:** a new Scan Training section in Motif. Existing puzzle mode and game collections stay unchanged.
- **v1:** quick scan, flag call, move, feedback, random quiet positions.
- **v2:** full scan (targets, arrows, final check), stats, Caïssa export.
- **Not planned:** live help in chess.com games.
