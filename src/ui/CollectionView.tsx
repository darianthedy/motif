import type { PuzzleRecord } from '../model/derive';
import { statsFor } from '../model/derive';
import type { Collection } from '../model/puzzle';
import type { SessionMode } from '../model/session';
import { OfflineNote } from './OfflineNote';

interface Props {
  collection: Collection;
  puzzleIds: string[];
  records: Map<string, PuzzleRecord>;
  /** Puzzles left in the collection's run, or null when there is none to resume. */
  remaining: number | null;
  online: boolean;
  onStart: (mode: SessionMode) => void;
  onBrowse: () => void;
  onResume: () => void;
  onDiscardRun: () => void;
  onDelete: () => void;
  onExit: () => void;
}

export function CollectionView({
  collection,
  puzzleIds,
  records,
  remaining,
  online,
  onStart,
  onBrowse,
  onResume,
  onDiscardRun,
  onDelete,
  onExit,
}: Props) {
  const stats = statsFor(puzzleIds, records);

  return (
    <div className="screen">
      <header className="screen-bar">
        <button type="button" className="link" onClick={onExit}>
          ← Collections
        </button>
        <h2>{collection.name}</h2>
      </header>

      <p className="muted small">
        {stats.total} puzzles · {stats.solved} solved · {stats.failed} to review ·{' '}
        {stats.unseen} new
      </p>

      {remaining !== null && (
        <div className="resume">
          <p className="muted small">A session is in progress — {remaining} left.</p>
          <div className="row">
            <button type="button" onClick={onResume}>
              Resume
            </button>
            <button type="button" className="link" onClick={onDiscardRun} disabled={!online}>
              Discard
            </button>
          </div>
        </div>
      )}

      <div className="menu">
        <button type="button" onClick={() => onStart('ordered')} disabled={stats.total === 0}>
          Solve in order
        </button>
        <button
          type="button"
          onClick={() => onStart('randomInCollection')}
          disabled={stats.total === 0}
        >
          Solve shuffled
        </button>
      </div>

      <div className="menu">
        <button type="button" onClick={onBrowse} disabled={stats.total === 0}>
          Browse puzzles
        </button>
      </div>

      <div className="menu subtle">
        <button
          type="button"
          className="link danger"
          disabled={!online}
          onClick={() => {
            if (confirm(`Delete "${collection.name}" and its puzzles?`)) onDelete();
          }}
        >
          Delete collection
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
