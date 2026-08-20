import { useCallback, useEffect, useRef, useState } from 'react';
import type { User } from '@supabase/supabase-js';
import type { AppState } from './model/state';
import { currentUser, onAuthChange, syncAvailable, syncOnce } from './model/supabase';

export type SyncStatus =
  | { kind: 'off' }
  | { kind: 'signedOut' }
  | { kind: 'idle'; at: number | null }
  | { kind: 'syncing' }
  | { kind: 'error'; message: string };

/** Quiet period after a change before pushing, so a session is not a write per move. */
const PUSH_DEBOUNCE_MS = 4000;

interface Options {
  state: AppState | null;
  /** Adopt the merged library returned by the server. */
  onMerged: (state: AppState) => void;
}

export function useSync({ state, onMerged }: Options) {
  const [user, setUser] = useState<User | null>(null);
  const [status, setStatus] = useState<SyncStatus>(
    syncAvailable ? { kind: 'signedOut' } : { kind: 'off' },
  );
  const timer = useRef<number | undefined>(undefined);
  // Read inside the debounced callback so it always pushes the latest library
  // rather than whatever it was when the timer was set.
  const latest = useRef(state);
  latest.current = state;
  const running = useRef(false);

  useEffect(() => {
    if (!syncAvailable) return;
    void currentUser().then(setUser);
    return onAuthChange((session) => setUser(session?.user ?? null));
  }, []);

  const run = useCallback(
    async (who: User) => {
      const current = latest.current;
      if (!current || running.current) return;
      running.current = true;
      setStatus({ kind: 'syncing' });
      try {
        const { state: merged } = await syncOnce(who.id, current);
        onMerged(merged);
        setStatus({ kind: 'idle', at: Date.now() });
      } catch (error) {
        setStatus({ kind: 'error', message: (error as Error).message });
      } finally {
        running.current = false;
      }
    },
    [onMerged],
  );

  // Sync once on sign-in: this is the moment a new device has nothing and the
  // remote has everything, so it is the one that makes the feature worth having.
  useEffect(() => {
    if (!user) {
      setStatus(syncAvailable ? { kind: 'signedOut' } : { kind: 'off' });
      return;
    }
    void run(user);
  }, [run, user]);

  // Push changes, debounced.
  useEffect(() => {
    if (!user || !state) return;
    clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void run(user), PUSH_DEBOUNCE_MS);
    return () => clearTimeout(timer.current);
  }, [run, state, user]);

  // A phone is backgrounded far more often than closed, and a debounced push
  // that never fires is a lost session.
  useEffect(() => {
    if (!user) return;
    const flush = () => {
      if (document.visibilityState === 'hidden') void run(user);
    };
    document.addEventListener('visibilitychange', flush);
    return () => document.removeEventListener('visibilitychange', flush);
  }, [run, user]);

  const syncNow = useCallback(() => {
    if (user) void run(user);
  }, [run, user]);

  return { user, status, syncNow };
}
