import { useCallback, useEffect, useRef, useState } from 'react';
import type { AppState } from './model/state';
import { currentUser, syncAvailable, transportFor } from './model/neon';
import type { SyncUser } from './model/neon';
import { rebase } from './model/rows';
import { syncRows } from './model/rowSync';

export type SyncStatus =
  | { kind: 'off' }
  | { kind: 'signedOut' }
  | { kind: 'idle'; at: number | null }
  | { kind: 'syncing' }
  | { kind: 'error'; message: string };

/** Quiet period after a change before pushing, so a session is not a write per move. */
const PUSH_DEBOUNCE_MS = 4000;

/**
 * Floor on the gap between syncs.
 *
 * A backstop, not the mechanism: the loop below is broken by not scheduling
 * pointless work, and this only bounds the damage if some future edit
 * reintroduces a cycle. Without it, a feedback loop is invisible locally and
 * shows up as a quota bill.
 */
const MIN_SYNC_INTERVAL_MS = 10_000;

interface Options {
  state: AppState | null;
  /** Functional state update, as useAppState's `update`. */
  adopt: (fn: (current: AppState) => AppState) => void;
}

export function useSync({ state, adopt }: Options) {
  const [user, setUser] = useState<SyncUser | null>(null);
  const [status, setStatus] = useState<SyncStatus>(
    syncAvailable ? { kind: 'signedOut' } : { kind: 'off' },
  );
  const timer = useRef<number | undefined>(undefined);
  /**
   * The library as it stood after the last completed sync.
   *
   * Compared by reference, which is exactly right for an immutable state that
   * is replaced wholesale: a genuine edit produces a new object, and a sync
   * that changed nothing leaves this pointing at the same one.
   */
  const synced = useRef<AppState | null>(null);
  const lastRunAt = useRef(0);
  // Read inside the debounced callback so it always pushes the latest library
  // rather than whatever it was when the timer was set.
  const latest = useRef(state);
  latest.current = state;
  const running = useRef(false);

  // Better Auth's vanilla client exposes no stable subscription, so the
  // session is read on mount and re-read after a sign-in or sign-out rather
  // than watched. Polling would be the alternative, and there is nothing to
  // poll for: the session only changes when this app changes it.
  const refreshUser = useCallback(async () => {
    if (!syncAvailable) return;
    setUser(await currentUser());
  }, []);

  useEffect(() => {
    void refreshUser();
  }, [refreshUser]);

  const run = useCallback(
    async (who: SyncUser, force = false) => {
      const current = latest.current;
      if (!current || running.current) return;
      if (!force && Date.now() - lastRunAt.current < MIN_SYNC_INTERVAL_MS) return;

      running.current = true;
      lastRunAt.current = Date.now();
      setStatus({ kind: 'syncing' });
      try {
        const merged = await syncRows(current, who.id, transportFor(who.id));

        // Recorded as synced *before* adopting, so the push effect that the
        // adoption triggers finds nothing to do. `syncRows` returns the very
        // same object when nothing moved, and otherwise a new one that this
        // marks as already pushed — either way no second sync follows. That
        // loop shipped once, and idled at ten requests every twenty seconds.
        synced.current = merged;
        if (merged !== current) {
          // Anything recorded during the round trip is in the live state but
          // not in `merged`; rebase replays it on top. If there was any, the
          // result differs from `merged`, so the push effect schedules the
          // next sync to send it — which is exactly right.
          adopt((live) => rebase(current, live, merged));
        }
        setStatus({ kind: 'idle', at: Date.now() });
      } catch (error) {
        setStatus({ kind: 'error', message: (error as Error).message });
      } finally {
        running.current = false;
      }
    },
    [adopt],
  );

  // Sync once on sign-in: this is the moment a new device has nothing and the
  // remote has everything, so it is the one that makes the feature worth having.
  useEffect(() => {
    if (!user) {
      setStatus(syncAvailable ? { kind: 'signedOut' } : { kind: 'off' });
      return;
    }
    // Forced: signing in is the moment a new device has nothing and the remote
    // has everything, so it must not be swallowed by the rate limit.
    void run(user, true);
  }, [run, user]);

  // Push changes, debounced. Nothing to push when the library has not moved
  // since the last sync, which is what stops the feedback loop at its source.
  useEffect(() => {
    if (!user || !state || state === synced.current) return;
    clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void run(user), PUSH_DEBOUNCE_MS);
    return () => clearTimeout(timer.current);
  }, [run, state, user]);

  // A phone is backgrounded far more often than closed, and a debounced push
  // that never fires is a lost session.
  useEffect(() => {
    if (!user) return;
    const flush = () => {
      // Forced: a backgrounded tab may never get another chance, and the point
      // of flushing is to not lose the session.
      if (document.visibilityState === 'hidden' && latest.current !== synced.current) {
        void run(user, true);
      }
    };
    document.addEventListener('visibilitychange', flush);
    return () => document.removeEventListener('visibilitychange', flush);
  }, [run, user]);

  // Explicit: the user asked, so neither the rate limit nor "nothing changed"
  // should make the button do nothing.
  const syncNow = useCallback(() => {
    if (user) void run(user, true);
  }, [run, user]);

  return { user, status, syncNow, refreshUser };
}
