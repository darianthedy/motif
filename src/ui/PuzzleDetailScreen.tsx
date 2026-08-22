import { useEffect, useMemo, useState } from 'react';
import { replayLine, startingFen, withPiece } from '../model/board';
import { moveFrom, moveTo } from '../model/move';
import { solverSide } from '../model/puzzle';
import type { Puzzle, PuzzleStatus } from '../model/puzzle';
import type { AppState } from '../model/state';
import { Board } from './Board';
import { describePlacement } from './MissingPieceView';

const STATUS_LABEL: Record<PuzzleStatus, string> = {
  solved: 'Solved',
  failed: 'To review',
  unseen: 'Not attempted',
};

interface Props {
  state: AppState;
  puzzle: Puzzle;
  onSaveComment: (comment: string) => void;
  onDelete: () => void;
  onExit: () => void;
}

/**
 * One puzzle, laid open.
 *
 * This is the only screen that shows a solution on purpose. Everything else
 * goes out of its way to hide the idea — tags and comments stay hidden until a
 * puzzle resolves — but browsing is a deliberate act, and a library you cannot
 * inspect is one you cannot correct. With puzzles arriving from OCR, being able
 * to see the line and delete a bad one matters more than the spoiler.
 */
export function PuzzleDetailScreen({ state, puzzle, onSaveComment, onDelete, onExit }: Props) {
  const [lineIndex, setLineIndex] = useState(0);
  const [ply, setPly] = useState(0);
  const [comment, setComment] = useState(puzzle.comment ?? '');
  const [saved, setSaved] = useState(false);

  const start = useMemo(
    () => startingFen(puzzle.fen, puzzle.setupMove),
    [puzzle.fen, puzzle.setupMove],
  );
  const steps = useMemo(
    () => replayLine(puzzle.fen, puzzle.setupMove, puzzle.solutions[lineIndex] ?? []),
    [lineIndex, puzzle],
  );
  // A missing-piece puzzle is browsed as the position with its answer already
  // in it: there is no line to step through, and the whole point of this screen
  // is to see whether the answer is right.
  const placed = useMemo(
    () => (puzzle.addPiece ? withPiece(start, puzzle.addPiece) : null),
    [puzzle.addPiece, start],
  );

  // Switching lines rewinds; leaving the cursor where it was would show a
  // position from the previous variation.
  useEffect(() => {
    setPly(0);
  }, [lineIndex]);

  const progress = state.progress[puzzle.id];
  const status: PuzzleStatus = progress?.status ?? 'unseen';
  const missingPiece = puzzle.addPiece;
  const shown = missingPiece ? placed ?? start : ply === 0 ? start : steps[ply - 1]?.fen ?? start;
  const lastMove = ply > 0 ? steps[ply - 1]?.move : undefined;
  const truncated = !missingPiece && steps.length < (puzzle.solutions[lineIndex]?.length ?? 0);

  const save = () => {
    onSaveComment(comment);
    setSaved(true);
    window.setTimeout(() => setSaved(false), 1500);
  };

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← Puzzles
        </button>
        <h2>{puzzle.sourceId ? `#${puzzle.sourceId}` : 'Puzzle'}</h2>
      </header>

      <Board
        fen={shown}
        orientation={solverSide(puzzle)}
        // Read-only: this screen is for looking, and letting moves be made here
        // would raise the question of what they mean.
        onMove={() => {}}
        interactive={false}
        highlight={
          missingPiece
            ? { from: missingPiece.square, to: missingPiece.square }
            : lastMove
              ? { from: moveFrom(lastMove), to: moveTo(lastMove) }
              : null
        }
      />

      {missingPiece ? (
        <p className="replay answer">
          {describePlacement(missingPiece)}
          {!placed && <span className="bad small"> — which is not a legal placement</span>}
        </p>
      ) : (
      <div className="replay">
        {/* Latin-1 guillemet rather than U+23EE: that codepoint has an emoji
            presentation and renders as a tofu box in the system font, the same
            trap the pawn glyph fell into. */}
        <button type="button" className="link" disabled={ply === 0} onClick={() => setPly(0)}>
          «
        </button>
        <button
          type="button"
          className="link"
          disabled={ply === 0}
          onClick={() => setPly((p) => p - 1)}
        >
          ←
        </button>
        <span className="moves">
          {steps.length === 0 && <span className="muted small">No playable line</span>}
          {steps.map((step, index) => (
            <button
              key={`${step.move}-${index}`}
              type="button"
              className="move"
              data-current={index + 1 === ply || undefined}
              data-solver={step.bySolver || undefined}
              onClick={() => setPly(index + 1)}
            >
              {step.san}
            </button>
          ))}
        </span>
        <button
          type="button"
          className="link"
          disabled={ply >= steps.length}
          onClick={() => setPly((p) => p + 1)}
        >
          →
        </button>
      </div>
      )}

      {truncated && (
        <p className="bad small">
          The rest of this line is not playable from this position — the puzzle is faulty.
        </p>
      )}

      {puzzle.solutions.length > 1 && (
        <div className="filters">
          {puzzle.solutions.map((_, index) => (
            <button
              key={index}
              type="button"
              className="chip"
              data-active={index === lineIndex || undefined}
              onClick={() => setLineIndex(index)}
            >
              Line {index + 1}
            </button>
          ))}
        </div>
      )}

      <dl className="facts">
        <dt>Status</dt>
        <dd>
          {STATUS_LABEL[status]}
          {progress?.attempts
            ? ` · ${progress.attempts} attempt${progress.attempts === 1 ? '' : 's'}, ${progress.mistakes} mistake${progress.mistakes === 1 ? '' : 's'}`
            : ''}
        </dd>
        {puzzle.tags.length > 0 && (
          <>
            <dt>Motif</dt>
            <dd>{puzzle.tags.join(' · ')}</dd>
          </>
        )}
        {puzzle.rating && (
          <>
            <dt>Rating</dt>
            <dd>{puzzle.rating}</dd>
          </>
        )}
        <dt>FEN</dt>
        <dd className="fen">{puzzle.fen}</dd>
      </dl>

      <label className="field">
        <span className="muted small">Comment</span>
        <textarea
          value={comment}
          onChange={(event) => setComment(event.target.value)}
          rows={3}
          placeholder="What is the idea here?"
        />
      </label>
      <div className="row">
        <button type="button" onClick={save} disabled={comment === (puzzle.comment ?? '')}>
          {saved ? 'Saved' : 'Save comment'}
        </button>
      </div>

      <div className="menu subtle">
        <button
          type="button"
          className="link danger"
          onClick={() => {
            if (confirm('Delete this puzzle from the library?')) onDelete();
          }}
        >
          Delete puzzle
        </button>
      </div>
    </div>
  );
}
