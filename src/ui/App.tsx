import { useState } from 'react';
import type { Collection } from '../model/puzzle';
import type { PuzzleResult } from '../model/runner';
import { orderForGlobalDraw, startSession } from '../model/session';
import type { SessionMode } from '../model/session';
import {
  GLOBAL_SESSION,
  allPuzzles,
  clearSession,
  deleteCollection,
  deletePuzzle,
  failedPuzzleIds,
  puzzlesIn,
  recordResult,
  saveSession,
  setPuzzleComment,
} from '../model/state';
import type { AppState } from '../model/state';
import { useAppState } from '../useAppState';
import { useSync } from '../useSync';
import { AccountScreen } from './AccountScreen';
import { CollectionView } from './CollectionView';
import { Home } from './Home';
import { ImportScreen } from './ImportScreen';
import { PuzzleDetailScreen } from './PuzzleDetailScreen';
import { PuzzleListScreen } from './PuzzleListScreen';
import { SessionScreen } from './SessionScreen';
import './App.css';

/**
 * Says what an import actually did.
 *
 * Re-importing a file you already have is the common case, not an error — it is
 * how an edited comment reaches an existing puzzle. Reporting that as
 * "Added 0" reads like a failure, so the zero case gets its own sentence.
 */
function describeImport(added: number, refreshed: number): string {
  const plural = (n: number) => (n === 1 ? 'puzzle' : 'puzzles');
  if (added && refreshed) return `Added ${added} ${plural(added)}, refreshed ${refreshed}.`;
  if (added) return `Added ${added} ${plural(added)}.`;
  if (refreshed) return `No new puzzles — refreshed ${refreshed} you already had.`;
  return 'Nothing to add.';
}

type Route =
  | { name: 'home' }
  | { name: 'collection'; id: string }
  | { name: 'import' }
  | { name: 'account' }
  | { name: 'puzzles'; collectionId: string }
  | { name: 'puzzle'; collectionId: string; puzzleId: string }
  | { name: 'session'; key: string };

export function App() {
  const { state, update, replace } = useAppState();
  const [route, setRoute] = useState<Route>({ name: 'home' });
  // Sync adopts whatever the merge produced; it is a superset of what this
  // device had, so replacing local state with it never loses work.
  const { user, status, syncNow, refreshUser } = useSync({ state, onMerged: replace });
  const [notice, setNotice] = useState<string | null>(null);

  // The store is read asynchronously; rendering an empty library first would
  // flash "nothing here yet" over an existing collection on every launch.
  if (!state) return <main className="app" />;

  const collectionOf = (id: string) => state.collections.find((c) => c.id === id);

  const begin = (key: string, mode: SessionMode, collection?: Collection) => {
    let ids: string[];
    if (mode === 'reviewMistakes') {
      ids = failedPuzzleIds(state);
    } else if (collection) {
      ids = puzzlesIn(state, collection).map((puzzle) => puzzle.id);
    } else {
      // Bias the library-wide draw away from what was just seen, so two short
      // sessions in a row do not serve the same handful.
      ids = orderForGlobalDraw(
        allPuzzles(state).map((puzzle) => puzzle.id),
        state.recent,
      );
    }
    if (!ids.length) return;

    const session = startSession(mode, collection?.id ?? null, ids);
    update((current) => saveSession(current, key, session));
    setRoute({ name: 'session', key });
  };

  const onResult = (puzzleId: string, result: PuzzleResult, mistakes: number) => {
    update((current) => recordResult(current, puzzleId, result, mistakes));
  };

  if (route.name === 'session') {
    const session = state.sessions[route.key];
    if (!session) {
      setRoute({ name: 'home' });
      return <main className="app" />;
    }
    return (
      <main className="app">
        <SessionScreen
          session={session}
          puzzles={state.puzzles}
          onSession={(next) => update((current) => saveSession(current, route.key, next))}
          onResult={onResult}
          onFinished={() => {
            update((current) => clearSession(current, route.key));
            setRoute({ name: 'home' });
          }}
          // Stopping keeps the session: that is the whole point of resuming.
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  if (route.name === 'account') {
    return (
      <main className="app">
        <AccountScreen
          user={user}
          status={status}
          onSyncNow={syncNow}
          onAuthChanged={() => void refreshUser()}
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  if (route.name === 'import') {
    return (
      <main className="app">
        <ImportScreen
          state={state}
          onApply={(next: AppState, added, refreshed) => {
            replace(next);
            setNotice(describeImport(added, refreshed));
            setRoute({ name: 'home' });
          }}
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  if (route.name === 'puzzle') {
    const puzzle = state.puzzles[route.puzzleId];
    if (!puzzle) {
      setRoute({ name: 'puzzles', collectionId: route.collectionId });
      return <main className="app" />;
    }
    return (
      <main className="app">
        <PuzzleDetailScreen
          state={state}
          puzzle={puzzle}
          onSaveComment={(comment) =>
            update((current) => setPuzzleComment(current, puzzle.id, comment))
          }
          onDelete={() => {
            update((current) => deletePuzzle(current, puzzle.id));
            setRoute({ name: 'puzzles', collectionId: route.collectionId });
          }}
          onExit={() => setRoute({ name: 'puzzles', collectionId: route.collectionId })}
        />
      </main>
    );
  }

  if (route.name === 'puzzles') {
    const collection = collectionOf(route.collectionId);
    if (!collection) {
      setRoute({ name: 'home' });
      return <main className="app" />;
    }
    return (
      <main className="app">
        <PuzzleListScreen
          state={state}
          collection={collection}
          onOpen={(puzzle) =>
            setRoute({ name: 'puzzle', collectionId: collection.id, puzzleId: puzzle.id })
          }
          onExit={() => setRoute({ name: 'collection', id: collection.id })}
        />
      </main>
    );
  }

  if (route.name === 'collection') {
    const collection = collectionOf(route.id);
    if (!collection) {
      setRoute({ name: 'home' });
      return <main className="app" />;
    }
    return (
      <main className="app">
        <CollectionView
          state={state}
          collection={collection}
          onStart={(mode) => begin(collection.id, mode, collection)}
          onBrowse={() => setRoute({ name: 'puzzles', collectionId: collection.id })}
          onResume={() => setRoute({ name: 'session', key: collection.id })}
          onDiscardSession={() => update((current) => clearSession(current, collection.id))}
          onDelete={() => {
            update((current) => deleteCollection(current, collection.id));
            setRoute({ name: 'home' });
          }}
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  return (
    <main className="app">
      {notice && (
        <p className="notice" onClick={() => setNotice(null)}>
          {notice}
        </p>
      )}
      <Home
        state={state}
        onOpen={(collection) => setRoute({ name: 'collection', id: collection.id })}
        onGlobalRandom={() => begin(GLOBAL_SESSION, 'randomGlobal')}
        onReviewMistakes={() => begin('review', 'reviewMistakes')}
        onImport={() => setRoute({ name: 'import' })}
        onAccount={() => setRoute({ name: 'account' })}
        syncStatus={status}
        signedIn={Boolean(user)}
        onRestore={(restored) => {
          replace(restored);
          setNotice('Backup restored.');
        }}
      />
    </main>
  );
}
