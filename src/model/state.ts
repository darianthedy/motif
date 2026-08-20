import type { ImportResult } from './import/json';
import { contentKey, newProgress } from './puzzle';
import type { Collection, Progress, Puzzle } from './puzzle';
import type { PuzzleResult } from './runner';
import { RECENT_MEMORY } from './session';
import type { SessionState } from './session';

/** Key used for the library-wide session, which belongs to no collection. */
export const GLOBAL_SESSION = '*';

export interface AppState {
  version: 1;
  puzzles: Record<string, Puzzle>;
  collections: Collection[];
  /** Keyed by puzzle id. Global, not per collection. */
  progress: Record<string, Progress>;
  /** Suspended sessions, keyed by collection id or GLOBAL_SESSION. */
  sessions: Record<string, SessionState>;
  /** Recently served puzzle ids, most recent first. */
  recent: string[];
}

export function emptyState(): AppState {
  return { version: 1, puzzles: {}, collections: [], progress: {}, sessions: {}, recent: [] };
}

export function allPuzzles(state: AppState): Puzzle[] {
  return Object.values(state.puzzles);
}

export function puzzlesIn(state: AppState, collection: Collection): Puzzle[] {
  return collection.puzzleIds
    .map((id) => state.puzzles[id])
    .filter((puzzle): puzzle is Puzzle => Boolean(puzzle));
}

export function statusOf(state: AppState, puzzleId: string) {
  return state.progress[puzzleId]?.status ?? 'unseen';
}

export function failedPuzzleIds(state: AppState): string[] {
  return Object.values(state.progress)
    .filter((entry) => entry.status === 'failed' && state.puzzles[entry.puzzleId])
    .map((entry) => entry.puzzleId);
}

export interface CollectionStats {
  total: number;
  solved: number;
  failed: number;
  unseen: number;
}

export function statsFor(state: AppState, collection: Collection): CollectionStats {
  const stats: CollectionStats = { total: 0, solved: 0, failed: 0, unseen: 0 };
  for (const id of collection.puzzleIds) {
    if (!state.puzzles[id]) continue;
    stats.total++;
    const status = statusOf(state, id);
    if (status === 'solved') stats.solved++;
    else if (status === 'failed') stats.failed++;
    else stats.unseen++;
  }
  return stats;
}

/**
 * Merges an import into the library.
 *
 * Puzzles are identified by content key, so importing a file twice adds
 * nothing the second time but does refresh tags, comment, rating and source —
 * which is how an edited comment reaches an existing puzzle. Collection
 * membership is a set: re-importing into the same collection does not duplicate
 * entries, and the same puzzle can belong to several collections.
 */
export function applyImport(
  state: AppState,
  result: ImportResult,
  /**
   * Overrides the collection name. Only meaningful for a single-group file —
   * a multi-chapter import takes its names from the file, since one name
   * cannot describe eighteen chapters.
   */
  collectionName?: string,
): { state: AppState; added: number; refreshed: number; collections: number } {
  const puzzles = { ...state.puzzles };
  const byKey = new Map<string, string>();
  for (const puzzle of Object.values(puzzles)) byKey.set(contentKey(puzzle), puzzle.id);

  let collections = state.collections;
  let added = 0;
  let refreshed = 0;
  let touchedCollections = 0;

  const singleGroup = result.groups.length === 1;

  for (const group of result.groups) {
    const touchedIds: string[] = [];

    for (const incoming of group.puzzles) {
      const key = contentKey(incoming);
      const existingId = byKey.get(key);

      if (existingId) {
        // Identity is position + solutions, so everything else is metadata and
        // the newer file wins. The id is kept so progress survives a re-import.
        puzzles[existingId] = {
          ...puzzles[existingId],
          tags: incoming.tags,
          comment: incoming.comment,
          rating: incoming.rating ?? puzzles[existingId].rating,
          sourceId: incoming.sourceId ?? puzzles[existingId].sourceId,
        };
        touchedIds.push(existingId);
        refreshed++;
      } else {
        puzzles[incoming.id] = incoming;
        byKey.set(key, incoming.id);
        touchedIds.push(incoming.id);
        added++;
      }
    }

    const name = (singleGroup ? collectionName : undefined) ?? group.name ?? collectionName;
    if (!name || !touchedIds.length) continue;
    touchedCollections++;

    const existing = collections.find((collection) => collection.name === name);
    if (existing) {
      const merged = [...existing.puzzleIds];
      for (const id of touchedIds) if (!merged.includes(id)) merged.push(id);
      collections = collections.map((collection) =>
        collection.id === existing.id ? { ...collection, puzzleIds: merged } : collection,
      );
    } else {
      collections = [
        ...collections,
        { id: crypto.randomUUID(), name, createdAt: Date.now(), puzzleIds: [...touchedIds] },
      ];
    }
  }

  return {
    state: { ...state, puzzles, collections },
    added,
    refreshed,
    collections: touchedCollections,
  };
}

/**
 * Records the outcome of one attempt.
 *
 * Status always reflects the most recent attempt: a clean re-solve promotes a
 * failed puzzle to solved, and missing a previously solved puzzle demotes it.
 * "Failed" therefore means "needs work now" rather than "was once missed",
 * which is what makes review mode worth opening. `firstSolvedAt` is kept either
 * way, so the history of having solved it is not lost.
 */
export function recordResult(
  state: AppState,
  puzzleId: string,
  result: PuzzleResult,
  mistakes = 0,
  now = Date.now(),
): AppState {
  const previous = state.progress[puzzleId] ?? newProgress(puzzleId);
  const updated: Progress = {
    ...previous,
    status: result === 'solved' ? 'solved' : 'failed',
    attempts: previous.attempts + 1,
    mistakes: previous.mistakes + mistakes,
    lastAttemptAt: now,
    firstSolvedAt:
      previous.firstSolvedAt ?? (result === 'solved' ? now : undefined),
  };

  const recent = [puzzleId, ...state.recent.filter((id) => id !== puzzleId)].slice(
    0,
    RECENT_MEMORY,
  );

  return { ...state, progress: { ...state.progress, [puzzleId]: updated }, recent };
}

export function saveSession(state: AppState, key: string, session: SessionState): AppState {
  return { ...state, sessions: { ...state.sessions, [key]: session } };
}

export function clearSession(state: AppState, key: string): AppState {
  const sessions = { ...state.sessions };
  delete sessions[key];
  return { ...state, sessions };
}

export function renameCollection(state: AppState, id: string, name: string): AppState {
  return {
    ...state,
    collections: state.collections.map((collection) =>
      collection.id === id ? { ...collection, name } : collection,
    ),
  };
}

/**
 * Removes a collection, and with it any puzzle left in no other collection.
 *
 * Orphaned puzzles would otherwise linger in random-global sessions with no way
 * to see or delete them. Progress for a deleted puzzle goes too — keeping it
 * would resurrect stale stats if the same puzzle were imported again later.
 */
export function deleteCollection(state: AppState, id: string): AppState {
  const collections = state.collections.filter((collection) => collection.id !== id);
  const stillReferenced = new Set(collections.flatMap((collection) => collection.puzzleIds));

  const puzzles: Record<string, Puzzle> = {};
  for (const [puzzleId, puzzle] of Object.entries(state.puzzles)) {
    if (stillReferenced.has(puzzleId)) puzzles[puzzleId] = puzzle;
  }

  const progress: Record<string, Progress> = {};
  for (const [puzzleId, entry] of Object.entries(state.progress)) {
    if (stillReferenced.has(puzzleId)) progress[puzzleId] = entry;
  }

  const sessions = { ...state.sessions };
  delete sessions[id];

  return {
    ...state,
    collections,
    puzzles,
    progress,
    sessions,
    recent: state.recent.filter((puzzleId) => stillReferenced.has(puzzleId)),
  };
}
