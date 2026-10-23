import { useMemo, useState } from 'react';
import { SCOPE_ALL, SCOPE_REVIEW } from '../data/backend';
import type { AttemptResult, Collection, NewPuzzle, RunScope } from '../data/backend';
import { puzzleRecords, recentIds, reviewIds } from '../model/derive';
import type { ImportResult } from '../model/import/json';
import {
  allPuzzles,
  collectionsOf,
  planImport,
  progressOf,
  puzzlesIn,
  runIn,
} from '../model/library';
import { makeQueue, orderForGlobalDraw } from '../model/session';
import type { SessionMode } from '../model/session';
import { useLibrary } from '../useLibrary';
import { CollectionView } from './CollectionView';
import { Home } from './Home';
import { ImportScreen } from './ImportScreen';
import type { ImportTarget } from './ImportScreen';
import { PuzzleDetailScreen } from './PuzzleDetailScreen';
import { PuzzleListScreen } from './PuzzleListScreen';
import { SessionScreen } from './SessionScreen';
import { SignInScreen } from './SignInScreen';
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
  | { name: 'puzzles'; collectionId: string }
  | { name: 'puzzle'; collectionId: string; puzzleId: string }
  | { name: 'session'; scope: RunScope };

export function App() {
  const {
    user,
    library,
    loaded,
    online,
    status,
    pending,
    write,
    startRun,
    recordAttempt,
    signIn,
    signOut,
  } = useLibrary();
  const [route, setRoute] = useState<Route>({ name: 'home' });
  const [notice, setNotice] = useState<string | null>(null);
  const records = useMemo(() => puzzleRecords(library?.attempts ?? []), [library]);

  // Still finding out who is signed in.
  if (user === undefined) return <main className="app" />;

  if (user === null) {
    return (
      <main className="app">
        <SignInScreen online={online} onSubmit={signIn} />
      </main>
    );
  }

  // The cached copy is read asynchronously; rendering an empty library first
  // would flash "nothing here yet" over an existing collection on every launch.
  if (!library) {
    return (
      <main className="app">
        {loaded && (
          <div className="screen">
            <h1>Motif</h1>
            <p className="muted">
              {online
                ? status.kind === 'error'
                  ? `Could not load your library: ${status.message}`
                  : 'Loading your library…'
                : "You're offline, and this device has no copy of your library yet. " +
                  'Connect once to download it.'}
            </p>
          </div>
        )}
      </main>
    );
  }

  const collectionOf = (id: string) => library.collections.find((c) => c.id === id);

  const begin = (scope: RunScope, mode: SessionMode, ids: string[]) => {
    if (!ids.length) return;
    void startRun({
      id: crypto.randomUUID(),
      scope,
      mode,
      queue: makeQueue(mode, ids),
      startedAt: Date.now(),
    });
    setRoute({ name: 'session', scope });
  };

  /** Runs an online edit, reporting a failure rather than dropping it. */
  const edit = async (fn: Parameters<typeof write>[0], done?: string) => {
    try {
      await write(fn);
      if (done) setNotice(done);
      return true;
    } catch (error) {
      setNotice(`That didn't save: ${(error as Error).message}`);
      return false;
    }
  };

  /**
   * A single-collection file goes where the import screen says; a file of
   * several makes a new collection of each. Re-importing into a collection
   * updates the puzzles it already has rather than adding them twice.
   */
  const applyImport = async (result: ImportResult, target?: ImportTarget) => {
    const created: Collection[] = [];
    const puzzles: NewPuzzle[] = [];
    let added = 0;

    for (const group of result.groups) {
      if (!group.puzzles.length) continue;
      let collectionId: string;
      if (target && 'collectionId' in target) {
        collectionId = target.collectionId;
      } else {
        collectionId = crypto.randomUUID();
        created.push({
          id: collectionId,
          name: target?.name ?? group.name ?? 'Imported',
          // Apart, so a book's chapters keep their order.
          createdAt: Date.now() + created.length,
        });
      }
      const plan = planImport(puzzlesIn(library, collectionId), group.puzzles, collectionId);
      puzzles.push(...plan.puzzles);
      added += plan.added;
    }

    const saved = await edit(async (backend) => {
      await backend.createCollections(created);
      await backend.importPuzzles(puzzles);
    }, describeImport(added, puzzles.length - added));
    if (saved) setRoute({ name: 'home' });
  };

  const onAttempt = (runId: string, puzzleId: string) =>
    (result: AttemptResult, mistakes: number, hinted: boolean) =>
      void recordAttempt({
        id: crypto.randomUUID(),
        puzzleId,
        runId,
        result,
        mistakes,
        hinted,
        playedAt: Date.now(),
      });

  if (route.name === 'session') {
    const run = runIn(library, route.scope);
    if (!run) {
      setRoute({ name: 'home' });
      return <main className="app" />;
    }
    const progress = progressOf(library, run);
    return (
      <main className="app">
        <SessionScreen
          progress={progress}
          puzzles={library.puzzles}
          onAttempt={(result, mistakes, hinted) =>
            progress.current && onAttempt(run.id, progress.current)(result, mistakes, hinted)
          }
          onFinished={() => setRoute({ name: 'home' })}
          // Stopping keeps the run: that is the whole point of resuming.
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  if (route.name === 'import') {
    return (
      <main className="app">
        <ImportScreen
          collections={collectionsOf(library)}
          online={online}
          onApply={(result, target) => void applyImport(result, target)}
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  if (route.name === 'puzzle') {
    const puzzle = library.puzzles.find((p) => p.id === route.puzzleId);
    if (!puzzle) {
      setRoute({ name: 'puzzles', collectionId: route.collectionId });
      return <main className="app" />;
    }
    return (
      <main className="app">
        <PuzzleDetailScreen
          puzzle={puzzle}
          record={records.get(puzzle.id)}
          online={online}
          onSaveComment={(comment) => edit((backend) => backend.setComment(puzzle.id, comment))}
          onDelete={() =>
            void edit((backend) => backend.deletePuzzle(puzzle.id)).then((deleted) => {
              if (deleted) setRoute({ name: 'puzzles', collectionId: route.collectionId });
            })
          }
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
          collection={collection}
          puzzles={puzzlesIn(library, collection.id)}
          records={records}
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
    const puzzles = puzzlesIn(library, collection.id);
    const run = runIn(library, collection.id);
    const progress = run && progressOf(library, run);
    return (
      <main className="app">
        <CollectionView
          collection={collection}
          puzzleIds={puzzles.map((p) => p.id)}
          records={records}
          remaining={progress?.current ? progress.remaining : null}
          online={online}
          onStart={(mode) => begin(collection.id, mode, puzzles.map((p) => p.id))}
          onBrowse={() => setRoute({ name: 'puzzles', collectionId: collection.id })}
          onResume={() => setRoute({ name: 'session', scope: collection.id })}
          onDiscardRun={() => run && void edit((backend) => backend.deleteRun(run.id))}
          onRename={(name) => void edit((backend) => backend.renameCollection(collection.id, name))}
          onDelete={() =>
            void edit((backend) => backend.deleteCollection(collection.id)).then((deleted) => {
              if (deleted) setRoute({ name: 'home' });
            })
          }
          onExit={() => setRoute({ name: 'home' })}
        />
      </main>
    );
  }

  const everything = allPuzzles(library).map((p) => p.id);

  return (
    <main className="app">
      {notice && (
        <p className="notice" onClick={() => setNotice(null)}>
          {notice}
        </p>
      )}
      <Home
        library={library}
        collections={collectionsOf(library)}
        records={records}
        user={user}
        online={online}
        status={status}
        pending={pending}
        onOpen={(collection) => setRoute({ name: 'collection', id: collection.id })}
        onGlobalRandom={() =>
          // Biased away from what was just seen, so two short sessions in a
          // row do not serve the same handful.
          begin(SCOPE_ALL, 'randomGlobal', orderForGlobalDraw(everything, recentIds(library.attempts)))
        }
        onReviewMistakes={() => begin(SCOPE_REVIEW, 'reviewMistakes', reviewIds(everything, records))}
        onImport={() => setRoute({ name: 'import' })}
        onResetProgress={() =>
          void edit(
            (backend) => backend.resetProgress(),
            'Progress reset. Every puzzle is unseen again.',
          )
        }
        onSignOut={() => void signOut()}
      />
    </main>
  );
}
