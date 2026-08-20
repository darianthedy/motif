import { contentKey } from './puzzle';
import type { Collection, Progress, Puzzle } from './puzzle';
import { RECENT_MEMORY } from './session';
import type { SessionState } from './session';
import { emptyState } from './state';
import type { AppState } from './state';

/**
 * Merging two divergent libraries.
 *
 * Sync is whole-state rather than per-row, because the app is a blob everywhere
 * else and a normalized schema would be a second model to keep in step. What
 * makes a blob safe to sync is that it can be merged deterministically instead
 * of overwritten: last-write-wins would mean solving ten puzzles on a phone and
 * then losing them the moment a laptop with stale state pushed.
 *
 * The merge is deterministic and symmetric in effect — both devices computing
 * it independently reach the same library — which is what lets each one push
 * the result without further coordination.
 *
 * The subtle part is identity. Two devices that import the same file generate
 * different UUIDs for the same puzzle, so merging on id alone would double
 * every puzzle. Puzzles are therefore matched on `contentKey` — position plus
 * accepted solutions — and one id is chosen as canonical, with every reference
 * to the loser rewritten. Without that remap, progress and sessions would point
 * at puzzles that no longer exist.
 */

/** Deterministic winner: earliest addition, id as tiebreak so both sides agree. */
function preferred(a: Puzzle, b: Puzzle): Puzzle {
  if (a.addedAt !== b.addedAt) return a.addedAt < b.addedAt ? a : b;
  return a.id < b.id ? a : b;
}

/**
 * Metadata comes from the more recently added record, since a re-import is how
 * an edited comment arrives. Fields absent there fall back to the other, so a
 * refresh that drops a comment does not erase one already held.
 */
function mergeMetadata(canonical: Puzzle, a: Puzzle, b: Puzzle): Puzzle {
  const newer = a.addedAt >= b.addedAt ? a : b;
  const older = newer === a ? b : a;
  return {
    ...canonical,
    tags: newer.tags.length ? newer.tags : older.tags,
    comment: newer.comment ?? older.comment,
    rating: newer.rating ?? older.rating,
    sourceId: newer.sourceId ?? older.sourceId,
  };
}

/**
 * Counters take the max rather than the sum.
 *
 * Both devices count monotonically from a shared ancestor, so summing would
 * double-count every attempt they both already knew about. Max can undercount
 * when the two genuinely diverged, which is the right way to be wrong: a stat
 * that reads slightly low is a cosmetic loss, whereas an inflated one is a lie
 * that never settles.
 */
function mergeProgress(a: Progress, b: Progress): Progress {
  const newer = (a.lastAttemptAt ?? 0) >= (b.lastAttemptAt ?? 0) ? a : b;
  const firstSolved = [a.firstSolvedAt, b.firstSolvedAt].filter(
    (at): at is number => typeof at === 'number',
  );
  return {
    puzzleId: newer.puzzleId,
    // Status follows the most recent attempt on either device: it is a
    // statement about the last time this puzzle was seen, not a tally.
    status: newer.status,
    attempts: Math.max(a.attempts, b.attempts),
    mistakes: Math.max(a.mistakes, b.mistakes),
    lastAttemptAt: Math.max(a.lastAttemptAt ?? 0, b.lastAttemptAt ?? 0) || undefined,
    firstSolvedAt: firstSolved.length ? Math.min(...firstSolved) : undefined,
  };
}

export function mergeStates(local: AppState, remote: AppState): AppState {
  const merged = emptyState();

  // --- Puzzles, matched on content rather than id ---
  const byKey = new Map<string, Puzzle>();
  const idMap = new Map<string, string>();

  for (const source of [local, remote]) {
    for (const puzzle of Object.values(source.puzzles)) {
      const key = contentKey(puzzle);
      const existing = byKey.get(key);
      if (!existing) {
        byKey.set(key, puzzle);
        continue;
      }
      const canonical = mergeMetadata(preferred(existing, puzzle), existing, puzzle);
      byKey.set(key, canonical);
    }
  }

  for (const canonical of byKey.values()) merged.puzzles[canonical.id] = canonical;

  // Every id that lost, and the canonical id it now points at.
  for (const source of [local, remote]) {
    for (const puzzle of Object.values(source.puzzles)) {
      const canonical = byKey.get(contentKey(puzzle));
      if (canonical) idMap.set(puzzle.id, canonical.id);
    }
  }

  const remap = (id: string) => idMap.get(id) ?? id;
  const alive = (id: string) => Boolean(merged.puzzles[id]);

  // --- Collections, matched on name ---
  // Name is the handle everywhere else: imports merge into a collection of the
  // same name, so two devices importing the same file agree without ids.
  const collections = new Map<string, Collection>();
  for (const source of [local, remote]) {
    for (const collection of source.collections) {
      const existing = collections.get(collection.name);
      const ids = collection.puzzleIds.map(remap).filter(alive);

      if (!existing) {
        collections.set(collection.name, { ...collection, puzzleIds: [...new Set(ids)] });
        continue;
      }
      // Union, keeping the earlier collection's ordering and appending what
      // only the other side had — order is the collection's own and should not
      // be reshuffled by a sync.
      const union = [...existing.puzzleIds];
      for (const id of ids) if (!union.includes(id)) union.push(id);
      collections.set(collection.name, {
        ...existing,
        createdAt: Math.min(existing.createdAt, collection.createdAt),
        puzzleIds: union,
      });
    }
  }
  merged.collections = [...collections.values()].sort((a, b) => a.createdAt - b.createdAt);

  // --- Progress ---
  for (const source of [local, remote]) {
    for (const entry of Object.values(source.progress)) {
      const id = remap(entry.puzzleId);
      if (!alive(id)) continue;
      const moved = { ...entry, puzzleId: id };
      const existing = merged.progress[id];
      merged.progress[id] = existing ? mergeProgress(existing, moved) : moved;
    }
  }

  // --- Sessions ---
  // The more recently active session wins outright rather than being merged:
  // a queue and cursor are only meaningful together, and interleaving two of
  // them would produce a position neither device was ever in.
  for (const source of [local, remote]) {
    for (const [key, session] of Object.entries(source.sessions)) {
      const moved: SessionState = {
        ...session,
        queue: session.queue.map(remap).filter(alive),
        current: session.current ? remap(session.current) : null,
        retries: session.retries
          .map((retry) => ({ ...retry, puzzleId: remap(retry.puzzleId) }))
          .filter((retry) => alive(retry.puzzleId)),
        solvedIds: session.solvedIds.map(remap).filter(alive),
        failedIds: session.failedIds.map(remap).filter(alive),
      };
      if (!moved.queue.length) continue;

      const existing = merged.sessions[key];
      if (!existing || moved.lastActiveAt > existing.lastActiveAt) {
        merged.sessions[key] = moved;
      }
    }
  }

  // --- Recency ---
  // Interleaved by nothing better than order seen; it only biases a shuffle,
  // so approximate is fine.
  const recent: string[] = [];
  for (const id of [...local.recent, ...remote.recent].map(remap)) {
    if (alive(id) && !recent.includes(id)) recent.push(id);
  }
  merged.recent = recent.slice(0, RECENT_MEMORY);

  return merged;
}
