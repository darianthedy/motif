import type { Library } from '../data/backend';
import { statsFor } from '../model/derive';
import type { PuzzleRecord } from '../model/derive';
import { puzzlesIn, resumable } from '../model/library';
import type { Collection } from '../model/puzzle';
import { OfflineNote } from './OfflineNote';

interface Props {
  library: Library;
  collections: Collection[];
  records: Map<string, PuzzleRecord>;
  online: boolean;
  onOpen: (collection: Collection) => void;
  onGlobalRandom: () => void;
  onReviewMistakes: () => void;
  onImport: () => void;
  onResetProgress: () => void;
}

/** The Puzzles section's front page: the collections, and ways into them. */
export function PuzzlesHome({
  library,
  collections,
  records,
  online,
  onOpen,
  onGlobalRandom,
  onReviewMistakes,
  onImport,
  onResetProgress,
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
      <h1>Puzzles</h1>

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
        <OfflineNote online={online} />
      </div>
    </div>
  );
}
