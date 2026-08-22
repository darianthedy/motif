import { useMemo, useState } from 'react';
import { isMissingPiece, solverSide } from '../model/puzzle';
import type { Collection, Puzzle, PuzzleStatus } from '../model/puzzle';
import { puzzlesIn, statusOf } from '../model/state';
import type { AppState } from '../model/state';

const STATUS_LABEL: Record<PuzzleStatus, string> = {
  solved: 'solved',
  failed: 'to review',
  unseen: 'new',
};

type Filter = 'all' | PuzzleStatus;

interface Props {
  state: AppState;
  collection: Collection;
  onOpen: (puzzle: Puzzle) => void;
  onExit: () => void;
}

/**
 * The puzzles in a collection, in their own order.
 *
 * Deliberately shows status and index but not the position: a thumbnail per row
 * would be prettier and would also spoil the puzzle at a glance, which is the
 * same reason tags stay hidden while solving. You open a puzzle when you have
 * decided to look at it.
 */
export function PuzzleListScreen({ state, collection, onOpen, onExit }: Props) {
  const [filter, setFilter] = useState<Filter>('all');
  const puzzles = useMemo(() => puzzlesIn(state, collection), [collection, state]);

  const shown = puzzles.filter(
    (puzzle) => filter === 'all' || statusOf(state, puzzle.id) === filter,
  );

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← {collection.name}
        </button>
        <h2>Puzzles</h2>
      </header>

      <div className="filters">
        {(['all', 'unseen', 'failed', 'solved'] as Filter[]).map((option) => (
          <button
            key={option}
            type="button"
            className="chip"
            data-active={filter === option || undefined}
            onClick={() => setFilter(option)}
          >
            {option === 'all' ? 'All' : STATUS_LABEL[option]}
          </button>
        ))}
      </div>

      {shown.length === 0 ? (
        <p className="muted small">Nothing here.</p>
      ) : (
        <ol className="puzzle-list">
          {shown.map((puzzle) => {
            const status = statusOf(state, puzzle.id);
            // Its number in the collection, not in the filtered view, so the
            // position of a puzzle does not change when a filter is applied.
            const index = puzzles.indexOf(puzzle) + 1;
            return (
              <li key={puzzle.id}>
                <button type="button" className="puzzle-row" onClick={() => onOpen(puzzle)}>
                  <span className="muted index">{index}</span>
                  <span className="row-main">
                    {puzzle.sourceId
                      ? `#${puzzle.sourceId}`
                      : isMissingPiece(puzzle)
                        ? `${solverSide(puzzle) === 'w' ? 'White' : 'Black'} piece missing`
                        : `${solverSide(puzzle) === 'w' ? 'White' : 'Black'} to play`}
                  </span>
                  <span className="status" data-status={status}>
                    {STATUS_LABEL[status]}
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
      )}
    </div>
  );
}
