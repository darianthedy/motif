import type { Collection } from '../model/puzzle';
import type { SessionMode, SessionState } from '../model/session';
import { remainingCount } from '../model/session';
import { statsFor } from '../model/state';
import type { AppState } from '../model/state';

interface Props {
  state: AppState;
  collection: Collection;
  onStart: (mode: SessionMode) => void;
  onResume: () => void;
  onDiscardSession: () => void;
  onDelete: () => void;
  onExit: () => void;
}

export function CollectionView({
  state,
  collection,
  onStart,
  onResume,
  onDiscardSession,
  onDelete,
  onExit,
}: Props) {
  const stats = statsFor(state, collection);
  const saved: SessionState | undefined = state.sessions[collection.id];

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

      {saved && (
        <div className="resume">
          <p className="muted small">
            A session is in progress — {remainingCount(saved)} left.
          </p>
          <div className="row">
            <button type="button" onClick={onResume}>
              Resume
            </button>
            <button type="button" className="link" onClick={onDiscardSession}>
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

      <div className="menu subtle">
        <button
          type="button"
          className="link danger"
          onClick={() => {
            if (confirm(`Delete "${collection.name}" and its puzzles?`)) onDelete();
          }}
        >
          Delete collection
        </button>
      </div>
    </div>
  );
}
