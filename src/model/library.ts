import type { Library, NewPuzzle, Run, RunScope } from '../data/backend';
import { runProgress } from './derive';
import type { RunProgress } from './derive';
import { contentKey } from './puzzle';
import type { Collection, Puzzle, PuzzleContent } from './puzzle';

/** Collections in the order they were made. */
export function collectionsOf(library: Library): Collection[] {
  return [...library.collections].sort(
    (a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1),
  );
}

/** A collection's puzzles, in its own order. */
export function puzzlesIn(library: Library, collectionId: string): Puzzle[] {
  return library.puzzles
    .filter((puzzle) => puzzle.collectionId === collectionId)
    .sort((a, b) => a.position - b.position || (a.id < b.id ? -1 : 1));
}

/** Every puzzle, collection by collection. */
export function allPuzzles(library: Library): Puzzle[] {
  return collectionsOf(library).flatMap((collection) => puzzlesIn(library, collection.id));
}

export function runIn(library: Library, scope: RunScope): Run | undefined {
  return library.runs.find((run) => run.scope === scope);
}

export function progressOf(library: Library, run: Run): RunProgress {
  return runProgress(run, library.attempts, new Set(library.puzzles.map((p) => p.id)));
}

/** Whether `scope` has a run with puzzles still to serve. */
export function resumable(library: Library, scope: RunScope): boolean {
  const run = runIn(library, scope);
  return Boolean(run && progressOf(library, run).current);
}

/**
 * Puzzles from a file, ready to import into a collection.
 *
 * One the collection already has keeps its place, so re-importing a file
 * updates its puzzles where they stand; the rest go on the end, in file order.
 * Returns how many are new, so the import can say what it did.
 */
export function planImport(
  existing: Puzzle[],
  incoming: PuzzleContent[],
  collectionId: string,
): { puzzles: NewPuzzle[]; added: number } {
  const positions = new Map(existing.map((p) => [contentKey(p), p.position]));
  let next = existing.reduce((max, p) => Math.max(max, p.position + 1), 0);
  let added = 0;
  const puzzles = incoming.map((content) => {
    let position = positions.get(contentKey(content));
    if (position === undefined) {
      position = next++;
      added++;
    }
    return { ...content, collectionId, position };
  });
  return { puzzles, added };
}
