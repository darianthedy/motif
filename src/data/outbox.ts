import { get, update } from 'idb-keyval';
import type { Attempt, Backend, Library, Run } from './backend';

/**
 * Runs and attempts made on this device and not yet uploaded.
 *
 * The only writes that work offline. Both are inserts that never change
 * afterwards, so uploading them late can never conflict with anything: the
 * server keeps the newer run in a scope, and an attempt uploaded twice is
 * stored once. That is what makes it safe to retry the whole outbox whenever
 * there is a chance to.
 */
export interface Outbox {
  runs: Run[];
  attempts: Attempt[];
}

const key = (userId: string) => `motif:outbox:${userId}`;

export function emptyOutbox(): Outbox {
  return { runs: [], attempts: [] };
}

export async function readOutbox(userId: string): Promise<Outbox> {
  return (await get<Outbox>(key(userId))) ?? emptyOutbox();
}

export async function addToOutbox(userId: string, added: Partial<Outbox>): Promise<void> {
  await update<Outbox>(key(userId), (current = emptyOutbox()) => ({
    runs: [...current.runs, ...(added.runs ?? [])],
    attempts: [...current.attempts, ...(added.attempts ?? [])],
  }));
}

/**
 * Uploads everything waiting, runs first so their attempts can point at them.
 * Returns what was uploaded and what is waiting now: anything added while the
 * upload was in flight stays for the next one.
 */
export async function flushOutbox(
  userId: string,
  backend: Backend,
): Promise<{ uploaded: Outbox; outbox: Outbox }> {
  const pending = await readOutbox(userId);
  for (const run of pending.runs) await backend.saveRun(run);
  await backend.recordAttempts(pending.attempts);

  const runs = new Set(pending.runs.map((r) => r.id));
  const attempts = new Set(pending.attempts.map((a) => a.id));
  let outbox = emptyOutbox();
  await update<Outbox>(key(userId), (current = emptyOutbox()) => {
    outbox = {
      runs: current.runs.filter((r) => !runs.has(r.id)),
      attempts: current.attempts.filter((a) => !attempts.has(a.id)),
    };
    return outbox;
  });
  return { uploaded: pending, outbox };
}

/**
 * The library as this device should show it: the server's copy with the
 * outbox laid on top. A run waiting to upload replaces an older one in its
 * scope, exactly as it will on the server.
 */
export function overlay(library: Library, outbox: Outbox): Library {
  if (!outbox.runs.length && !outbox.attempts.length) return library;

  let runs = library.runs;
  for (const run of outbox.runs) {
    const held = runs.find((r) => r.scope === run.scope);
    if (held && held.startedAt >= run.startedAt) continue;
    runs = [...runs.filter((r) => r.scope !== run.scope), run];
  }

  const puzzles = new Set(library.puzzles.map((p) => p.id));
  const stored = new Set(library.attempts.map((a) => a.id));
  const attempts = [
    ...library.attempts,
    ...outbox.attempts.filter((a) => puzzles.has(a.puzzleId) && !stored.has(a.id)),
  ];

  return { ...library, runs, attempts };
}
