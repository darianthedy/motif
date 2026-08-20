import type { PuzzleResult } from './runner';

export type SessionMode =
  /** Collection order, as inserted. */
  | 'ordered'
  /** Every puzzle in one collection, shuffled. */
  | 'randomInCollection'
  /** Every puzzle in the library, shuffled. */
  | 'randomGlobal'
  /** Everything currently marked failed, shuffled. */
  | 'reviewMistakes';

/**
 * Puzzles to put between a miss and its retry, so the answer isn't just echoed
 * back while it's still in short-term memory.
 */
export const RETRY_GAP = 3;

/** Ceiling on puzzles waiting to be retried, so a bad run can't build a backlog. */
export const MAX_RETRIES = 10;

/**
 * How many recently seen puzzles to keep out of a random-global draw, so
 * consecutive short sessions don't loop over the same handful.
 */
export const RECENT_MEMORY = 24;

interface PendingRetry {
  puzzleId: string;
  /** Serve once this many puzzles have been completed. */
  readyAt: number;
}

/**
 * A resumable run through a collection.
 *
 * The queue is materialized up front rather than regenerated from a seed.
 * A seed is smaller, but replaying it correctly after the library changes
 * underneath the session is a class of bug not worth owning — and a stored
 * queue makes "no repeats within a session" and "resume exactly where I
 * stopped" trivially true.
 *
 * Missed puzzles are re-served later in the same session rather than only in a
 * separate review mode, which is why `completed` can exceed `queue.length`.
 */
export interface SessionState {
  id: string;
  collectionId: string | null;
  mode: SessionMode;
  queue: string[];
  /** Index of the next *fresh* puzzle in `queue`. */
  cursor: number;
  current: string | null;
  /** Puzzles finished, retries included. Drives retry scheduling. */
  completed: number;
  retries: PendingRetry[];
  /** Unique puzzle ids cleanly solved this run. */
  solvedIds: string[];
  /** Unique puzzle ids failed this run, including ones later retried clean. */
  failedIds: string[];
  startedAt: number;
  lastActiveAt: number;
}

export function shuffle<T>(items: T[], rand: () => number): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export function makeQueue(
  mode: SessionMode,
  orderedIds: string[],
  rand: () => number = Math.random,
): string[] {
  return mode === 'ordered' ? [...orderedIds] : shuffle(orderedIds, rand);
}

export function startSession(
  mode: SessionMode,
  collectionId: string | null,
  orderedIds: string[],
  rand: () => number = Math.random,
  now = Date.now(),
): SessionState {
  const queue = makeQueue(mode, orderedIds, rand);
  return {
    id: crypto.randomUUID(),
    collectionId,
    mode,
    queue,
    cursor: queue.length ? 1 : 0,
    current: queue[0] ?? null,
    completed: 0,
    retries: [],
    solvedIds: [],
    failedIds: [],
    startedAt: now,
    lastActiveAt: now,
  };
}

export function isFinished(session: SessionState): boolean {
  return session.current === null;
}

/**
 * Fraction of the *original* queue solved, 0–1.
 *
 * Measured against `queue.length` rather than against everything served, so
 * re-injected retries never make the bar slip backwards. A retry is extra work
 * toward the same fixed goal, and a progress bar that retreats when you make a
 * mistake reads as a punishment rather than as information.
 */
export function progress(session: SessionState): number {
  if (!session.queue.length) return 1;
  return Math.min(1, session.solvedIds.length / session.queue.length);
}

export function remainingCount(session: SessionState): number {
  const fresh = Math.max(0, session.queue.length - session.cursor);
  return fresh + session.retries.length + (session.current ? 1 : 0);
}

/**
 * Records a result for the current puzzle and serves the next one.
 *
 * A missed puzzle is queued to come round again after `RETRY_GAP` others. Due
 * retries are served ahead of fresh puzzles, so the session drains its backlog
 * rather than saving it all for the end.
 */
export function completeCurrent(
  session: SessionState,
  result: PuzzleResult,
  now = Date.now(),
): SessionState {
  const finishedId = session.current;
  if (!finishedId) return session;

  const completed = session.completed + 1;
  const solvedIds =
    result === 'solved' && !session.solvedIds.includes(finishedId)
      ? [...session.solvedIds, finishedId]
      : session.solvedIds;
  const failedIds =
    result === 'failed' && !session.failedIds.includes(finishedId)
      ? [...session.failedIds, finishedId]
      : session.failedIds;

  let retries = session.retries;
  if (result === 'failed' && retries.length < MAX_RETRIES) {
    retries = [...retries, { puzzleId: finishedId, readyAt: completed + RETRY_GAP }];
  }

  // A retry that has waited long enough comes first; otherwise draw fresh.
  const dueIndex = retries.findIndex((r) => r.readyAt <= completed);
  let cursor = session.cursor;
  let next: string | null;

  if (dueIndex >= 0) {
    next = retries[dueIndex].puzzleId;
    retries = retries.filter((_, i) => i !== dueIndex);
  } else if (cursor < session.queue.length) {
    next = session.queue[cursor];
    cursor++;
  } else if (retries.length) {
    // Nothing fresh left, so serve the backlog early rather than stopping with
    // known-failed puzzles still owed a second look.
    next = retries[0].puzzleId;
    retries = retries.slice(1);
  } else {
    next = null;
  }

  return {
    ...session,
    cursor,
    current: next,
    completed,
    retries,
    solvedIds,
    failedIds,
    lastActiveAt: now,
  };
}

/**
 * Moves past the current puzzle without recording anything.
 *
 * Not a failure: a puzzle you cannot play is the library's fault, not yours,
 * and marking it failed would fill review mode with puzzles that can never be
 * solved. Nor is it a retry — a skipped puzzle does not come back this session.
 */
export function skipCurrent(session: SessionState, now = Date.now()): SessionState {
  if (!session.current) return session;

  let cursor = session.cursor;
  let retries = session.retries;
  let next: string | null;

  const dueIndex = retries.findIndex((r) => r.readyAt <= session.completed);
  if (dueIndex >= 0) {
    next = retries[dueIndex].puzzleId;
    retries = retries.filter((_, i) => i !== dueIndex);
  } else if (cursor < session.queue.length) {
    next = session.queue[cursor];
    cursor++;
  } else if (retries.length) {
    next = retries[0].puzzleId;
    retries = retries.slice(1);
  } else {
    next = null;
  }

  return { ...session, cursor, retries, current: next, lastActiveAt: now };
}

/**
 * Drops puzzles that no longer exist, keeping the current one where possible.
 * Called on resume, because a collection can be edited between sessions.
 */
export function reconcile(session: SessionState, existing: Set<string>): SessionState {
  const queue = session.queue.filter((id) => existing.has(id));
  const retries = session.retries.filter((r) => existing.has(r.puzzleId));
  if (queue.length === session.queue.length && retries.length === session.retries.length) {
    return session;
  }

  // Keep the cursor pointing at the same *unserved* position in the new queue.
  const served = new Set(session.queue.slice(0, session.cursor));
  const cursor = queue.filter((id) => served.has(id)).length;

  let current = session.current;
  if (current && !existing.has(current)) {
    current = queue[cursor] ?? retries[0]?.puzzleId ?? null;
  }

  return {
    ...session,
    queue,
    retries,
    cursor,
    current,
    solvedIds: session.solvedIds.filter((id) => existing.has(id)),
    failedIds: session.failedIds.filter((id) => existing.has(id)),
  };
}

/**
 * Random-global draw order, biased away from puzzles just seen.
 *
 * Recently seen puzzles go to the back rather than being removed: with a small
 * library, excluding them outright could leave nothing to draw, and "nothing
 * left" is not an answer a puzzle app should ever give.
 */
export function orderForGlobalDraw(
  allIds: string[],
  recentIds: string[],
  rand: () => number = Math.random,
): string[] {
  const recent = new Set(recentIds.slice(0, RECENT_MEMORY));
  const fresh = shuffle(allIds.filter((id) => !recent.has(id)), rand);
  const stale = shuffle(allIds.filter((id) => recent.has(id)), rand);
  return [...fresh, ...stale];
}
