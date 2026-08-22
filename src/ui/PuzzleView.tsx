import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { applyUci, isLegal, replayLine, startingFen } from '../model/board';
import { moveFrom, moveTo, stripQueenPromotion } from '../model/move';
import type { Uci } from '../model/move';
import { solverSide } from '../model/puzzle';
import type { Puzzle } from '../model/puzzle';
import { PuzzleRunner, REPLY_MS } from '../model/runner';
import type { PuzzleResult } from '../model/runner';
import { Board } from './Board';

type Phase = 'setup' | 'solving' | 'solved' | 'failed';

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

interface Props {
  puzzle: Puzzle;
  /** `mistakes` is the count for this attempt, for cumulative stats. */
  onComplete: (result: PuzzleResult, mistakes: number) => void;
  /** Move past a puzzle without recording a result. */
  onSkip: () => void;
}

export function PuzzleView({ puzzle, onComplete, onSkip }: Props) {
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

      if (outcome.reply) {
        const reply = outcome.reply;
        after(REPLY_MS, () => {
          const replied = applyUci(next, reply);
          if (replied) {
            setFen(replied);
            setHighlight({ from: moveFrom(reply), to: moveTo(reply) });
          }
        });
        return;
      }

      if (outcome.finished) {
        // Both outcomes stop here. The post-mortem — comment, motif, every
        // accepted line — is the part worth reading, and a clean solve is
        // exactly when you have the attention to read it. Advancing is always
        // a deliberate press.
        setPhase(runner.result === 'solved' ? 'solved' : 'failed');
      }
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

        {phase === 'solving' && !unplayable && !hint && (
          <span className="muted">
            {solverSide(puzzle) === 'w' ? 'White' : 'Black'} to play
          </span>
        )}

        {phase === 'solving' && !unplayable && hint && (
          <span className="hint">Play the highlighted move</span>
        )}

        {done && (
          <div className="result">
            {phase === 'solved' ? (
              <p className="good">Solved</p>
            ) : (
              <p className="bad">
                Missed{runner.hinted ? ' — answer shown' : ''} · {runner.mistakes} wrong move
                {runner.mistakes === 1 ? '' : 's'}
              </p>
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
