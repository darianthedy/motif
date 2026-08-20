import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { applyUci, isLegal, sanFor, startingFen } from '../model/board';
import { moveFrom, moveTo } from '../model/move';
import type { Uci } from '../model/move';
import { solverSide } from '../model/puzzle';
import type { Puzzle } from '../model/puzzle';
import { PuzzleRunner, REPLY_MS } from '../model/runner';
import type { PuzzleResult } from '../model/runner';
import { Board } from './Board';

/**
 * How long a clean solve is left on screen before moving on.
 *
 * Short and unskippable rather than a card you have to dismiss. Being right is
 * the unremarkable case — a confirmation step between every puzzle doubles how
 * long a session takes and teaches nothing. Only a miss stops the flow.
 */
const SOLVED_PAUSE_MS = 700;

type Phase = 'setup' | 'solving' | 'solved' | 'failed';

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
        const result = runner.result;
        setPhase(result === 'solved' ? 'solved' : 'failed');
        // A clean solve moves on by itself; a miss waits for you to look at it.
        if (result === 'solved') {
          after(SOLVED_PAUSE_MS, () => onComplete('solved', runner.mistakes));
        }
      }
    },
    [after, fen, onComplete, phase, runner],
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
  const alternatives = phase === 'failed' ? runner.otherFirstMoves : [];

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

        {phase === 'solved' && <span className="good">Solved</span>}

        {phase === 'failed' && (
          <div className="result">
            <p className="bad">
              Missed{runner.hinted ? ' — answer shown' : ''}
            </p>
            {/* Tags and comment appear only now. Before the puzzle resolves
                they give the idea away, which is the whole difficulty. */}
            {puzzle.comment && <p className="comment">{puzzle.comment}</p>}
            {puzzle.tags.length > 0 && (
              <p className="tags">{puzzle.tags.join(' · ')}</p>
            )}
            {alternatives.length > 0 && (
              <p className="muted">
                {alternatives.length} other first move
                {alternatives.length === 1 ? '' : 's'} also worked:{' '}
                {alternatives
                  .map((move) => sanFor(solverStart, move) ?? move)
                  .join(', ')}
              </p>
            )}
            <button type="button" onClick={() => onComplete('failed', runner.mistakes)}>
              Continue
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
