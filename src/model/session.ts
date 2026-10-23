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

export function shuffle<T>(items: T[], rand: () => number): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * The order a run serves its puzzles in. The library-wide draw arrives already
 * shuffled by `orderForGlobalDraw`, with what was just seen at the back, and
 * shuffling it again would undo that.
 */
export function makeQueue(
  mode: SessionMode,
  orderedIds: string[],
  rand: () => number = Math.random,
): string[] {
  return mode === 'ordered' || mode === 'randomGlobal'
    ? [...orderedIds]
    : shuffle(orderedIds, rand);
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
