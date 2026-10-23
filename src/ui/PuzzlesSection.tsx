import { useEffect, useMemo } from 'react';
import { SCOPE_ALL, SCOPE_REVIEW } from '../data/backend';
import type {
  Attempt,
  AttemptResult,
  Backend,
  Collection,
  Library,
  NewPuzzle,
  Run,
  RunScope,
} from '../data/backend';
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
import { CollectionView } from './CollectionView';
import { ImportScreen } from './ImportScreen';
import type { ImportTarget } from './ImportScreen';
import { PuzzleDetailScreen } from './PuzzleDetailScreen';
import { PuzzleListScreen } from './PuzzleListScreen';
import { PuzzlesHome } from './PuzzlesHome';
import { SessionScreen } from './SessionScreen';

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

export type PuzzlesRoute =
  | { name: 'home' }
  | { name: 'collection'; id: string }
  | { name: 'import' }
  | { name: 'puzzles'; collectionId: string }
  | { name: 'puzzle'; collectionId: string; puzzleId: string }
  | { name: 'session'; scope: RunScope };

/**
 * Somewhere else instead, for a screen whose puzzle or collection has gone —
 * deleted here, or on another device. The route lives in App, so it changes
 * after rendering rather than during it.
 */
function Redirect({ to, onNavigate }: { to: PuzzlesRoute; onNavigate: (route: PuzzlesRoute) => void }) {
  useEffect(() => onNavigate(to));
  return null;
}

interface Props {
  library: Library;
  online: boolean;
  route: PuzzlesRoute;
  onNavigate: (route: PuzzlesRoute) => void;
  /** Runs an online edit, reporting a failure rather than dropping it. */
  edit: (fn: (backend: Backend) => Promise<void>, done?: string) => Promise<boolean>;
  startRun: (run: Run) => Promise<void>;
  recordAttempt: (attempt: Attempt) => Promise<void>;
}

/** Collections, solving, and everything about the puzzles themselves. */
export function PuzzlesSection({
  library,
  online,
  route,
  onNavigate: setRoute,
  edit,
  startRun,
  recordAttempt,
}: Props) {
  const records = useMemo(() => puzzleRecords(library.attempts), [library]);

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
      return <Redirect to={{ name: 'home' }} onNavigate={setRoute} />;
    }
    const progress = progressOf(library, run);
    return (
      <SessionScreen
        progress={progress}
        puzzles={library.puzzles}
        online={online}
        onFlag={(puzzle, flagged) => void edit((backend) => backend.setFlagged(puzzle.id, flagged))}
        onAttempt={(result, mistakes, hinted) =>
          progress.current && onAttempt(run.id, progress.current)(result, mistakes, hinted)
        }
        onFinished={() => setRoute({ name: 'home' })}
        // Stopping keeps the run: that is the whole point of resuming.
        onExit={() => setRoute({ name: 'home' })}
      />
    );
  }

  if (route.name === 'import') {
    return (
      <ImportScreen
        collections={collectionsOf(library)}
        online={online}
        onApply={(result, target) => void applyImport(result, target)}
        onExit={() => setRoute({ name: 'home' })}
      />
    );
  }

  if (route.name === 'puzzle') {
    const puzzle = library.puzzles.find((p) => p.id === route.puzzleId);
    if (!puzzle) {
      return <Redirect to={{ name: 'puzzles', collectionId: route.collectionId }} onNavigate={setRoute} />;
    }
    return (
      <PuzzleDetailScreen
        puzzle={puzzle}
        record={records.get(puzzle.id)}
        online={online}
        onSaveComment={(comment) => edit((backend) => backend.setComment(puzzle.id, comment))}
        onFlag={(flagged) => void edit((backend) => backend.setFlagged(puzzle.id, flagged))}
        onDelete={() =>
          void edit((backend) => backend.deletePuzzle(puzzle.id)).then((deleted) => {
            if (deleted) setRoute({ name: 'puzzles', collectionId: route.collectionId });
          })
        }
        onExit={() => setRoute({ name: 'puzzles', collectionId: route.collectionId })}
      />
    );
  }

  if (route.name === 'puzzles') {
    const collection = collectionOf(route.collectionId);
    if (!collection) {
      return <Redirect to={{ name: 'home' }} onNavigate={setRoute} />;
    }
    return (
      <PuzzleListScreen
        collection={collection}
        puzzles={puzzlesIn(library, collection.id)}
        records={records}
        onOpen={(puzzle) =>
          setRoute({ name: 'puzzle', collectionId: collection.id, puzzleId: puzzle.id })
        }
        onExit={() => setRoute({ name: 'collection', id: collection.id })}
      />
    );
  }

  if (route.name === 'collection') {
    const collection = collectionOf(route.id);
    if (!collection) {
      return <Redirect to={{ name: 'home' }} onNavigate={setRoute} />;
    }
    const puzzles = puzzlesIn(library, collection.id);
    const run = runIn(library, collection.id);
    const progress = run && progressOf(library, run);
    return (
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
    );
  }

  const everything = allPuzzles(library).map((p) => p.id);

  return (
    <PuzzlesHome
      library={library}
      collections={collectionsOf(library)}
      records={records}
      online={online}
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
    />
  );
}
