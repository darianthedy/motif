import { useRef } from 'react';
import { exportState, parseState } from '../model/storage';
import { allPuzzles, failedPuzzleIds, statsFor } from '../model/state';
import type { AppState } from '../model/state';
import type { Collection } from '../model/puzzle';

interface Props {
  state: AppState;
  onOpen: (collection: Collection) => void;
  onGlobalRandom: () => void;
  onReviewMistakes: () => void;
  onImport: () => void;
  onRestore: (state: AppState) => void;
}

export function Home({
  state,
  onOpen,
  onGlobalRandom,
  onReviewMistakes,
  onImport,
  onRestore,
}: Props) {
  const restoreInput = useRef<HTMLInputElement>(null);
  const total = allPuzzles(state).length;
  const failed = failedPuzzleIds(state).length;

  const download = () => {
    const blob = new Blob([exportState(state)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `motif-backup-${new Date().toISOString().slice(0, 10)}.json`;
    link.click();
    URL.revokeObjectURL(url);
  };

  const restore = async (file: File | undefined) => {
    if (!file) return;
    try {
      onRestore(parseState(JSON.parse(await file.text())));
    } catch (error) {
      alert(`Could not read that backup: ${(error as Error).message}`);
    }
  };

  return (
    <div className="screen">
      <h1>Motif</h1>

      {total === 0 ? (
        <p className="muted">
          Nothing here yet. Import a collection to start.
        </p>
      ) : (
        <p className="muted small">
          {total} puzzle{total === 1 ? '' : 's'} in {state.collections.length} collection
          {state.collections.length === 1 ? '' : 's'}
        </p>
      )}

      <ul className="collections">
        {state.collections.map((collection) => {
          const stats = statsFor(state, collection);
          const resumable = Boolean(state.sessions[collection.id]);
          return (
            <li key={collection.id}>
              <button type="button" className="card" onClick={() => onOpen(collection)}>
                <span className="card-title">
                  {collection.name}
                  {resumable && <span className="pill">in progress</span>}
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
        <button type="button" onClick={onImport}>
          Import puzzles
        </button>
      </div>

      {/* Export is not a nicety here. iOS evicts script-writable storage for
          origins it considers unused, and `navigator.storage.persist()` is a
          request rather than a guarantee — puzzles can be re-imported, solve
          history cannot. */}
      <div className="menu subtle">
        <button type="button" className="link" onClick={download} disabled={total === 0}>
          Export backup
        </button>
        <button type="button" className="link" onClick={() => restoreInput.current?.click()}>
          Restore from backup
        </button>
        <input
          ref={restoreInput}
          type="file"
          accept=".json"
          style={{ display: 'none' }}
          onChange={(event) => void restore(event.target.files?.[0])}
        />
      </div>
    </div>
  );
}
