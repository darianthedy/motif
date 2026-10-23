import { useEffect, useMemo, useState } from 'react';
import { replayLine, withPiece } from '../model/board';
import type { PuzzleRecord } from '../model/derive';
import { moveFrom, moveTo } from '../model/move';
import { solverSide } from '../model/puzzle';
import type { Puzzle, PuzzleStatus } from '../model/puzzle';
import { Board } from './Board';
import { describePlacement } from './MissingPieceView';
import { OfflineNote } from './OfflineNote';

const STATUS_LABEL: Record<PuzzleStatus, string> = {
  solved: 'Solved',
  failed: 'To review',
  unseen: 'Not attempted',
};

interface Props {
  puzzle: Puzzle;
  /** Its attempts so far; none when it has not been played. */
  record: PuzzleRecord | undefined;
  online: boolean;
  /** Resolves once saved, to whether it was. */
  onSaveComment: (comment: string) => Promise<boolean>;
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
export function PuzzleDetailScreen({
  puzzle,
  record,
  online,
  onSaveComment,
  onDelete,
  onExit,
}: Props) {
  const [lineIndex, setLineIndex] = useState(0);
  const [ply, setPly] = useState(0);
  const [comment, setComment] = useState(puzzle.comment ?? '');
  const [saving, setSaving] = useState<'idle' | 'saving' | 'saved'>('idle');

  const start = puzzle.fen;
  const steps = useMemo(
    () => replayLine(puzzle.fen, puzzle.solutions[lineIndex] ?? []),
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

  const status: PuzzleStatus = record?.status ?? 'unseen';
  const missingPiece = puzzle.addPiece;
  const shown = missingPiece ? placed ?? start : ply === 0 ? start : steps[ply - 1]?.fen ?? start;
  const lastMove = ply > 0 ? steps[ply - 1]?.move : undefined;

  const save = async () => {
    setSaving('saving');
    const ok = await onSaveComment(comment);
    setSaving(ok ? 'saved' : 'idle');
    if (ok) window.setTimeout(() => setSaving('idle'), 1500);
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
          {record?.attempts
            ? ` · ${record.attempts} attempt${record.attempts === 1 ? '' : 's'}, ${record.mistakes} mistake${record.mistakes === 1 ? '' : 's'}`
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
        <button
          type="button"
          onClick={() => void save()}
          disabled={!online || saving === 'saving' || comment.trim() === (puzzle.comment ?? '')}
        >
          {saving === 'saved' ? 'Saved' : saving === 'saving' ? 'Saving…' : 'Save comment'}
        </button>
      </div>

      <div className="menu subtle">
        <button
          type="button"
          className="link danger"
          disabled={!online}
          onClick={() => {
            if (confirm('Delete this puzzle from the library?')) onDelete();
          }}
        >
          Delete puzzle
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
