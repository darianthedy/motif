import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { applyUci, isLegal, replayLine, sanFor, startingFen } from '../model/board';
import { moveFrom, moveTo, stripQueenPromotion } from '../model/move';
import type { Uci } from '../model/move';
import { solverSide } from '../model/puzzle';
import type { Puzzle } from '../model/puzzle';
import { PuzzleRunner, REPLY_MS } from '../model/runner';
import type { PuzzleResult } from '../model/runner';
import { Board } from './Board';
import { MissingPieceView } from './MissingPieceView';

/**
 * `replying` is the window while the opponent's scripted answer animates: the
 * solver's move is on the board but the reply is not, so the position on screen
 * is one the next expected move is not written for. Its own phase rather than a
 * flag, because the thing it controls is whether the board takes input.
 */
type Phase = 'setup' | 'solving' | 'replying' | 'solved' | 'failed';

/**
 * Whether two UCI strings name the same move, tolerating the queening
 * shorthand the trie already accepts: a played `e7e8q` matches a stored `e7e8`.
 */
function sameMove(a: Uci, b: Uci): boolean {
  return a === b || stripQueenPromotion(a) === b || stripQueenPromotion(b) === a;
}

/**
 * Whether `line` is the one just played, so the card can mark it.
 *
 * Compares only the solver's plies — the even ones — because the opponent's
 * replies are scripted and never chosen. A run always ends on a terminal node,
 * so the accepted moves identify exactly one line even where several share a
 * prefix.
 */
function playedLine(line: Uci[], accepted: Uci[]): boolean {
  const solverMoves = line.filter((_, ply) => ply % 2 === 0);
  return (
    solverMoves.length === accepted.length &&
    solverMoves.every((move, index) => sameMove(move, accepted[index]))
  );
}

const ORDINALS = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th'];

/** "2nd", for naming which move of the line broke. */
function ordinal(index: number): string {
  return ORDINALS[index] ?? `${index + 1}th`;
}

/**
 * "on move 2 of 3" — the part of the failure headline that says *where* the
 * line broke.
 *
 * Null for a one-move puzzle, where there is only one move it could have been
 * and saying so is noise.
 */
function whereItBroke(plies: number[], total: number): string | null {
  if (plies.length === 0 || total <= 1) return null;
  const numbers = plies.map((ply) => ply + 1);
  if (numbers.length === 1) return `on move ${numbers[0]} of ${total}`;
  const last = numbers[numbers.length - 1];
  return `on moves ${numbers.slice(0, -1).join(', ')} and ${last} of ${total}`;
}

interface Props {
  puzzle: Puzzle;
  /** `mistakes` is the count for this attempt, for cumulative stats. */
  onComplete: (result: PuzzleResult, mistakes: number) => void;
  /** Move past a puzzle without recording a result. */
  onSkip: () => void;
}

/**
 * One puzzle, of whichever kind it is.
 *
 * The kind is read off the puzzle rather than passed in, and the two views are
 * separate components: a session hands over a puzzle and gets back a result,
 * and nothing above here — the session, the queue, the progress bar — needs to
 * know which sort of question was asked.
 */
export function PuzzleView(props: Props) {
  const { puzzle } = props;
  if (puzzle.addPiece) {
    return <MissingPieceView {...props} addPiece={puzzle.addPiece} />;
  }
  return <MovePuzzleView {...props} />;
}

function MovePuzzleView({ puzzle, onComplete, onSkip }: Props) {
  const runner = useMemo(() => new PuzzleRunner(puzzle), [puzzle]);
  const solverStart = useMemo(
    () => startingFen(puzzle.fen, puzzle.setupMove),
    [puzzle],
  );

  const [fen, setFen] = useState(puzzle.setupMove ? puzzle.fen : solverStart);
  const [phase, setPhase] = useState<Phase>(puzzle.setupMove ? 'setup' : 'solving');
  const [highlight, setHighlight] = useState<{ from: string; to: string } | null>(null);
  const [hint, setHint] = useState<Uci | null>(null);
  const [shakeKey, setShakeKey] = useState(0);
  const timers = useRef<number[]>([]);
  /**
   * The position each of the solver's moves was asked from, indexed by move.
   *
   * The runner records a wrong move as UCI, having no board; SAN is what the
   * card should show, and SAN only exists relative to a position. This is that
   * position, kept as it goes past rather than reconstructed at the end —
   * reconstruction would mean replaying a line that, by definition, was not the
   * one played.
   */
  const askedFrom = useRef<string[]>([]);

  const after = useCallback((ms: number, fn: () => void) => {
    timers.current.push(window.setTimeout(fn, ms));
  }, []);

  // Every timer is owned by the puzzle that scheduled it. Without this an
  // opponent reply queued for a puzzle you have already left lands on the next
  // one's board.
  useEffect(() => {
    return () => {
      timers.current.forEach(clearTimeout);
      timers.current = [];
      // Positions belong to the puzzle they were asked from, for the same
      // reason the timers do.
      askedFrom.current = [];
    };
  }, [puzzle.id]);

  // The opponent's move into the position, played so it is seen rather than
  // presented as a fait accompli.
  useEffect(() => {
    if (phase !== 'setup' || !puzzle.setupMove) return;
    const move = puzzle.setupMove;
    after(REPLY_MS, () => {
      setFen(startingFen(puzzle.fen, move));
      setHighlight({ from: moveFrom(move), to: moveTo(move) });
      setPhase('solving');
    });
  }, [after, phase, puzzle.fen, puzzle.setupMove]);

  const onMove = useCallback(
    (move: Uci) => {
      if (phase !== 'solving') return;

      askedFrom.current[runner.accepted.length] = fen;
      const outcome = runner.submit(move);

      if (outcome.kind === 'wrong') {
        setShakeKey((key) => key + 1);
        // The board is never updated, so the position reverts by simply not
        // moving. Nothing to undo.
        if (runner.shouldRevealHint) {
          const revealed = runner.revealHint();
          if (revealed) setHint(revealed);
        }
        return;
      }

      const next = applyUci(fen, move);
      if (!next) return;
      setFen(next);
      setHighlight({ from: moveFrom(move), to: moveTo(move) });
      setHint(null);

      // Both outcomes stop the puzzle. The post-mortem — comment, motif, every
      // accepted line — is the part worth reading, and a clean solve is exactly
      // when you have the attention to read it. Advancing is always a
      // deliberate press.
      const resolved: Phase = runner.result === 'solved' ? 'solved' : 'failed';

      if (outcome.reply) {
        const reply = outcome.reply;
        setPhase('replying');
        after(REPLY_MS, () => {
          const replied = applyUci(next, reply);
          if (replied) {
            setFen(replied);
            setHighlight({ from: moveFrom(reply), to: moveTo(reply) });
          }
          // A line may end on the opponent's move. Resolving after the reply has
          // landed rather than before is the whole point of authoring it that
          // way: the last move is something you watch, not something the result
          // card tells you about.
          setPhase(outcome.finished ? resolved : 'solving');
        });
        return;
      }

      if (outcome.finished) setPhase(resolved);
    },
    [after, fen, phase, runner],
  );

  /**
   * A puzzle whose expected move cannot be played at all.
   *
   * The importer rejects these, but a library predating that check — or one
   * restored from an old backup — can still hold one, and there is no way to
   * finish it: the board will never accept the move the hint points at. Say so
   * and offer a way out, rather than letting the session stick.
   */
  const expected = runner.expectedMove;
  const unplayable =
    phase === 'solving' && expected !== null && !isLegal(fen, expected);

  const hintSquares = hint ? { from: moveFrom(hint), to: moveTo(hint) } : null;
  const done = phase === 'solved' || phase === 'failed';
  // The status line reads the same while a reply animates as it does while you
  // are being asked, so a mid-line reply doesn't blink the text out and back.
  const asking = phase === 'solving' || phase === 'replying';

  // Every accepted line, in SAN, for the card at the end. Built only once the
  // puzzle has resolved: replaying costs a board per ply, and before then it is
  // the one thing on the screen that must not exist.
  const lines = useMemo(() => {
    if (!done) return [];
    return puzzle.solutions.map((line) => {
      const steps = replayLine(puzzle.fen, puzzle.setupMove, line);
      return {
        steps,
        // A line the board will not play through: shown as far as it goes
        // rather than silently cut, since that is how a bad import surfaces.
        truncated: steps.length < line.length,
        played: playedLine(line, runner.accepted),
      };
    });
  }, [done, puzzle, runner]);

  // The line that was actually played, and how many moves of it were yours:
  // the denominator in "move 2 of 3".
  const played = lines.find((line) => line.played);
  const solverMoves = played
    ? played.steps.filter((step) => step.bySolver).length
    : runner.accepted.length;

  /**
   * Wrong moves grouped by the move they were played for, each group carrying
   * the move that was wanted instead.
   *
   * Grouped rather than listed flat because the question a failed puzzle raises
   * is "where did I go wrong", and three tries at one move is a different
   * answer to that than one try at each of three.
   */
  const missed = useMemo(() => {
    if (!done || runner.misses.length === 0) return [];
    const groups = new Map<number, string[]>();
    for (const miss of runner.misses) {
      const from = askedFrom.current[miss.ply];
      // Falling back to the raw UCI keeps a mistake visible even if the
      // position it was played in somehow went missing.
      const san = (from && sanFor(from, miss.move)) || miss.move;
      groups.set(miss.ply, [...(groups.get(miss.ply) ?? []), san]);
    }
    return [...groups].map(([ply, tried]) => ({
      ply,
      tried,
      wanted: played?.steps[ply * 2]?.san ?? null,
    }));
  }, [done, played, runner]);

  const broke = whereItBroke(
    missed.map((group) => group.ply),
    solverMoves,
  );

  return (
    <div className="puzzle">
      <Board
        fen={fen}
        orientation={solverSide(puzzle)}
        onMove={onMove}
        highlight={hintSquares ?? highlight}
        shakeKey={shakeKey}
        interactive={phase === 'solving'}
      />

      <div className="puzzle-status">
        {phase === 'setup' && <span className="muted">…</span>}

        {unplayable && (
          <div className="result">
            <p className="bad">This puzzle looks broken — its answer is not a legal move.</p>
            <button type="button" onClick={onSkip}>
              Skip it
            </button>
          </div>
        )}

        {asking && !unplayable && !hint && (
          <span className="muted">
            {solverSide(puzzle) === 'w' ? 'White' : 'Black'} to play
          </span>
        )}

        {asking && !unplayable && hint && (
          <span className="hint">Play the highlighted move</span>
        )}

        {done && (
          <div className="result">
            {phase === 'solved' ? (
              <p className="good">Solved</p>
            ) : (
              <p className="bad">
                Missed{broke ? ` ${broke}` : ''} · {runner.mistakes} wrong move
                {runner.mistakes === 1 ? '' : 's'}
                {runner.hinted ? ' · answer shown' : ''}
              </p>
            )}

            {/* What you played, against what was wanted. Directly under the
                verdict, because on a failed puzzle it is the thing being looked
                for — the comment and the full lines are read after. */}
            {missed.length > 0 && (
              <div className="misses">
                {missed.map((group) => (
                  <div key={group.ply} className="miss">
                    {solverMoves > 1 && (
                      <span className="muted small miss-label">{ordinal(group.ply)}</span>
                    )}
                    <span className="moves">
                      {group.tried.map((san, index) => (
                        <span key={`${san}-${index}`} className="move wrong">
                          {san}
                        </span>
                      ))}
                      {group.wanted && (
                        <>
                          <span className="muted small">→</span>
                          <span className="move" data-solver>
                            {group.wanted}
                          </span>
                        </>
                      )}
                    </span>
                  </div>
                ))}
              </div>
            )}

            {/* Tags and comment appear only now. Before the puzzle resolves
                they give the idea away, which is the whole difficulty. */}
            {puzzle.comment && <p className="comment">{puzzle.comment}</p>}
            {puzzle.tags.length > 0 && <p className="tags">{puzzle.tags.join(' · ')}</p>}

            <div className="solutions">
              {lines.map((line, index) => (
                <div key={index} className="solution" data-played={line.played || undefined}>
                  {lines.length > 1 && (
                    <span className="muted small line-label">{index + 1}</span>
                  )}
                  <span className="moves">
                    {line.steps.map((step, ply) => (
                      <span
                        key={`${step.move}-${ply}`}
                        className="move"
                        data-solver={step.bySolver || undefined}
                      >
                        {step.san}
                      </span>
                    ))}
                    {line.truncated && <span className="move bad">…</span>}
                  </span>
                </div>
              ))}
            </div>

            <button type="button" onClick={() => onComplete(runner.result, runner.mistakes)}>
              Continue
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
