import type { User } from '../data/account';
import type { Library } from '../data/backend';
import { statsFor } from '../model/derive';
import type { PuzzleRecord } from '../model/derive';
import { puzzlesIn, resumable } from '../model/library';
import type { Collection } from '../model/puzzle';
import type { SyncStatus } from '../useLibrary';
import { OfflineNote } from './OfflineNote';

interface Props {
  library: Library;
  collections: Collection[];
  records: Map<string, PuzzleRecord>;
  user: User;
  online: boolean;
  status: SyncStatus;
  /** Runs and attempts waiting to upload. */
  pending: number;
  onOpen: (collection: Collection) => void;
  onGlobalRandom: () => void;
  onReviewMistakes: () => void;
  onImport: () => void;
  onResetProgress: () => void;
  onSignOut: () => void;
}

export function Home({
  library,
  collections,
  records,
  user,
  online,
  status,
  pending,
  onOpen,
  onGlobalRandom,
  onReviewMistakes,
  onImport,
  onResetProgress,
  onSignOut,
}: Props) {
  const total = library.puzzles.length;
  const ids = new Set(library.puzzles.map((p) => p.id));
  const failed = [...records].filter(([id, r]) => r.status === 'failed' && ids.has(id)).length;
  const attempted = [...records.keys()].filter((id) => ids.has(id)).length;

  const resetProgress = () => {
    if (
      !confirm(
        `Forget every attempt on ${attempted} puzzle${attempted === 1 ? '' : 's'}?\n\n` +
          'Your puzzles and collections stay. Solved, mistakes and in-progress ' +
          'sessions are cleared, on every device.',
      )
    )
      return;
    onResetProgress();
  };

  return (
    <div className="screen">
      <h1>Motif</h1>

      {!online && (
        <p className="offline small">
          Offline{pending > 0 && ` · ${pending} to upload`}
        </p>
      )}
      {online && status.kind === 'error' && (
        <p className="bad small">Couldn't reach the server: {status.message}</p>
      )}

      {total === 0 ? (
        <p className="muted">Nothing here yet. Import a collection to start.</p>
      ) : (
        <p className="muted small">
          {total} puzzle{total === 1 ? '' : 's'} in {collections.length} collection
          {collections.length === 1 ? '' : 's'}
        </p>
      )}

      <ul className="collections">
        {collections.map((collection) => {
          const stats = statsFor(
            puzzlesIn(library, collection.id).map((p) => p.id),
            records,
          );
          return (
            <li key={collection.id}>
              <button type="button" className="card" onClick={() => onOpen(collection)}>
                <span className="card-title">
                  {collection.name}
                  {resumable(library, collection.id) && <span className="pill">in progress</span>}
                </span>
                <span className="muted small">
                  {stats.total} puzzles · {stats.solved} solved
                  {stats.failed > 0 && ` · ${stats.failed} to review`}
                </span>
                <span className="bar">
                  <span
                    className="bar-fill"
                    style={{ width: `${stats.total ? (stats.solved / stats.total) * 100 : 0}%` }}
                  />
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      {total > 0 && (
        <div className="menu">
          <button type="button" onClick={onGlobalRandom}>
            Random from everything
          </button>
          <button type="button" onClick={onReviewMistakes} disabled={failed === 0}>
            Review mistakes{failed > 0 && ` (${failed})`}
          </button>
        </div>
      )}

      <div className="menu">
        <button type="button" onClick={onImport} disabled={!online}>
          Import puzzles
        </button>
      </div>

      <div className="menu subtle">
        <button
          type="button"
          className="link danger"
          onClick={resetProgress}
          disabled={attempted === 0 || !online}
        >
          Reset progress
        </button>
        <button type="button" className="link" onClick={onSignOut} disabled={!online}>
          Sign out of {user.email}
        </button>
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
