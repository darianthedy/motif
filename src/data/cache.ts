import { get, set } from 'idb-keyval';
import { emptyLibrary } from './backend';
import type { Library } from './backend';

/**
 * This device's read-only copy of the account's library, so the app opens and
 * solves offline.
 *
 * Never edited, only replaced: each time the server is reached the copy is
 * overwritten with what it returned. Losing it loses nothing but the outbox,
 * which is kept separately (outbox.ts).
 */

const key = (userId: string) => `motif:cache:${userId}`;

export async function loadCache(userId: string): Promise<Library | null> {
  try {
    const cached = await get<Library>(key(userId));
    // A copy saved before games existed has no games yet, rather than none at all.
    return cached ? { ...emptyLibrary(), ...cached } : null;
  } catch {
    // An unreadable copy is the same as none: the next refresh replaces it.
    return null;
  }
}

export async function saveCache(userId: string, library: Library): Promise<void> {
  await set(key(userId), library);
}

/**
 * Ask the browser to exempt this origin from storage eviction.
 *
 * iOS clears script-writable storage after about seven days of disuse for
 * sites that are not installed to the home screen. A request, not a
 * guarantee; but it is free to ask, and the outbox is the one thing here that
 * exists nowhere else.
 */
export async function requestPersistence(): Promise<boolean> {
  if (!navigator.storage?.persist) return false;
  try {
    if (await navigator.storage.persisted()) return true;
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}
