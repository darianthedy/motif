import { useCallback, useMemo, useState } from 'react';
import { startingFen, withPiece } from '../model/board';
import { placementText, solverSide } from '../model/puzzle';
import type { PieceType, Placement, Puzzle } from '../model/puzzle';
import { MissingPieceRunner } from '../model/runner';
import type { PuzzleResult } from '../model/runner';
import { Board } from './Board';

/**
 * The missing-piece kind: no move to find, a piece to put back.
 *
 * The position is one piece short of the idea — mate, a fork, a pin — and the
 * question is which piece and where. It is the same puzzle in reverse: instead
 * of being shown a tactic and asked for the move, you are shown the shape a
 * tactic leaves behind and asked what would have to be standing there.
 *
 * Its own component rather than a branch inside `PuzzleView`, because they
 * share almost nothing: no line to walk, no opponent reply, no promotion, no
 * animation between plies. What they do share is the shape of the ending — a
 * card, always, with the comment and the answer on it — and the rules about
 * what costs a mistake, and those live in the runner.
 */

const PIECE_NAME: Record<PieceType, string> = {
  q: 'queen',
  r: 'rook',
  b: 'bishop',
  n: 'knight',
  p: 'pawn',
  k: 'king',
};

/** "White knight on g6" — for the answer, which is only ever shown at the end. */
export function describePlacement(placement: Placement): string {
  const color = placement.color === 'w' ? 'White' : 'Black';
  return `${color} ${PIECE_NAME[placement.type]} on ${placement.square}`;
}

type Phase = 'solving' | 'solved' | 'failed';

interface Props {
  puzzle: Puzzle;
  addPiece: Placement;
  onComplete: (result: PuzzleResult, mistakes: number) => void;
  onSkip: () => void;
}

export function MissingPieceView({ puzzle, addPiece, onComplete, onSkip }: Props) {
  const runner = useMemo(
    () => new MissingPieceRunner(puzzle, addPiece),
    [addPiece, puzzle],
  );

  const start = useMemo(
    () => startingFen(puzzle.fen, puzzle.setupMove),
    [puzzle.fen, puzzle.setupMove],
  );
  // The position with the answer in it, computed once. Also the check for
  // whether the puzzle is answerable at all.
  const answered = useMemo(() => withPiece(start, addPiece), [addPiece, start]);

  const [phase, setPhase] = useState<Phase>('solving');
  const [hint, setHint] = useState<Placement | null>(null);
  const [shakeKey, setShakeKey] = useState(0);

  const onPlace = useCallback(
    (square: string, type: PieceType) => {
      if (phase !== 'solving') return;

      const outcome = runner.submit(square, type);
      if (outcome.kind === 'wrong') {
        // Nothing is added to the board, so there is nothing to take back —
        // the same reason a wrong move never has to be undone.
        setShakeKey((key) => key + 1);
        if (runner.shouldRevealHint) {
          const revealed = runner.revealHint();
          if (revealed) setHint(revealed);
        }
        return;
      }

      setPhase(runner.result === 'solved' ? 'solved' : 'failed');
    },
    [phase, runner],
  );

  const done = phase !== 'solving';
  const side = solverSide(puzzle);
  const sideName = side === 'w' ? 'white' : 'black';

  // The answer goes on the board when the puzzle resolves — after a miss as
  // much as after a solve. Being told the piece and left to picture it on the
  // square is the part that would not stick.
  const shown = done && answered ? answered : start;
  const marked = done || hint ? { from: addPiece.square, to: addPiece.square } : null;

  return (
    <div className="puzzle">
      <Board
        fen={shown}
        orientation={side}
        onMove={() => {}}
        placing={phase === 'solving' && answered ? { color: addPiece.color, onPlace } : null}
        highlight={marked}
        shakeKey={shakeKey}
        interactive={phase === 'solving'}
      />

      <div className="puzzle-status">
        {!answered && (
          <div className="result">
            <p className="bad">This puzzle looks broken — its piece cannot go where it says.</p>
            <button type="button" onClick={onSkip}>
              Skip it
            </button>
          </div>
        )}

        {phase === 'solving' && answered && !hint && (
          <span className="muted">Add a {sideName} piece</span>
        )}

        {phase === 'solving' && answered && hint && (
          <span className="hint">
            Add the {PIECE_NAME[hint.type]} on the highlighted square
          </span>
        )}

        {done && (
          <div className="result">
            {phase === 'solved' ? (
              <p className="good">Solved</p>
            ) : (
              <p className="bad">
                Missed{runner.hinted ? ' — answer shown' : ''} · {runner.mistakes} wrong guess
                {runner.mistakes === 1 ? '' : 'es'}
              </p>
            )}

            {/* Withheld until now for the same reason as everywhere else: the
                comment names the idea, and naming it is the puzzle. */}
            {puzzle.comment && <p className="comment">{puzzle.comment}</p>}
            {puzzle.tags.length > 0 && <p className="tags">{puzzle.tags.join(' · ')}</p>}

            <div className="solutions">
              <div className="solution" data-played>
                <span className="moves">
                  <span className="move" data-solver>
                    {placementText(addPiece)}
                  </span>
                  <span className="muted small">{describePlacement(addPiece)}</span>
                </span>
              </div>
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
