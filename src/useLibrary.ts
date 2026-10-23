import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { account } from './data/account';
import type { User } from './data/account';
import type { Attempt, Backend, Library, Run } from './data/backend';
import { loadCache, requestPersistence, saveCache } from './data/cache';
import { addToOutbox, emptyOutbox, flushOutbox, overlay, readOutbox } from './data/outbox';
import type { Outbox } from './data/outbox';

/**
 * The signed-in account's library, as this device sees it.
 *
 * The database is the source of truth. Edits are written straight to it and
 * then the whole library is read back; the local copy (cache.ts) is only for
 * opening and solving offline. The one thing written locally first is play —
 * runs and attempts — which waits in the outbox until it can be uploaded.
 */

export type SyncStatus =
  | { kind: 'idle' }
  | { kind: 'syncing' }
  | { kind: 'error'; message: string };

/**
 * Who was last signed in on this device, so the app can open offline, when
 * the auth service cannot be asked.
 */
const USER_KEY = 'motif:user';

function rememberedUser(): User | null {
  try {
    const stored = localStorage.getItem(USER_KEY);
    return stored ? (JSON.parse(stored) as User) : null;
  } catch {
    return null;
  }
}

function remember(user: User | null) {
  try {
    if (user) localStorage.setItem(USER_KEY, JSON.stringify(user));
    else localStorage.removeItem(USER_KEY);
  } catch {
    // Only costs opening offline next time.
  }
}

function useOnline(): boolean {
  const [online, setOnline] = useState(navigator.onLine);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);
  return online;
}

export function useLibrary() {
  const online = useOnline();
  // Undefined while it is still being worked out; null is signed out.
  const [user, setUser] = useState<User | null | undefined>(() => rememberedUser() ?? undefined);
  // What the server last returned, or the cached copy of it. Null until either
  // is read, and stays null offline on a device that has never been online.
  const [base, setBase] = useState<Library | null>(null);
  const [outbox, setOutbox] = useState<Outbox>(emptyOutbox);
  const [loaded, setLoaded] = useState(false);
  const [status, setStatus] = useState<SyncStatus>({ kind: 'idle' });

  const backend = useMemo<Backend | null>(() => (user ? account.backend(user) : null), [user]);
  const library = useMemo(() => (base ? overlay(base, outbox) : null), [base, outbox]);

  // Read in callbacks that outlive a render: an event listener, the end of an
  // upload.
  const live = useRef({ user, backend, online });
  live.current = { user, backend, online };

  // Ask the auth service who is signed in, when it can be asked. Offline, the
  // remembered account stands, so the cached library can still open.
  useEffect(() => {
    if (!online) {
      setUser((current) => (current === undefined ? null : current));
      return;
    }
    let cancelled = false;
    account
      .currentUser()
      .catch(() => null)
      .then((found) => {
        if (cancelled) return;
        remember(found);
        // Kept as the same object when it is the same account, so nothing reloads.
        setUser((current) => (current && found && current.id === found.id ? current : found));
      });
    return () => {
      cancelled = true;
    };
  }, [online]);

  // The cached copy and the outbox, as soon as the account is known.
  useEffect(() => {
    setBase(null);
    setOutbox(emptyOutbox());
    setLoaded(false);
    if (!user) return;
    let cancelled = false;
    void Promise.all([loadCache(user.id), readOutbox(user.id)]).then(([cached, pending]) => {
      if (cancelled) return;
      setBase((current) => current ?? cached);
      setOutbox(pending);
      setLoaded(true);
      void requestPersistence();
    });
    return () => {
      cancelled = true;
    };
  }, [user]);

  // One upload at a time; a second request waits for the first rather than
  // sending the same rows alongside it.
  const flushing = useRef<Promise<void> | null>(null);

  const flush = useCallback(async () => {
    const { user, backend, online } = live.current;
    if (!user || !backend || !online) return;
    while (flushing.current) await flushing.current;
    const run = (async () => {
      const { uploaded, outbox } = await flushOutbox(user.id, backend);
      if (live.current.user?.id !== user.id) return;
      // Uploaded rows are the server's now: keep showing them until the next
      // read brings them back from there.
      setBase((current) => current && overlay(current, uploaded));
      setOutbox(outbox);
    })();
    flushing.current = run;
    try {
      await run;
    } finally {
      flushing.current = null;
    }
  }, []);

  /** Uploads the outbox, then replaces the local copy with the server's. */
  const refresh = useCallback(async () => {
    const { user, backend, online } = live.current;
    if (!user || !backend || !online) return;
    setStatus({ kind: 'syncing' });
    try {
      await flush();
      const fresh = await backend.load();
      if (live.current.user?.id !== user.id) return;
      await saveCache(user.id, fresh);
      setBase(fresh);
      setOutbox(await readOutbox(user.id));
      setStatus({ kind: 'idle' });
    } catch (error) {
      setStatus({ kind: 'error', message: (error as Error).message });
    }
  }, [flush]);

  // On open, on coming back online, and on returning to the foreground.
  useEffect(() => {
    if (loaded && online) void refresh();
  }, [loaded, online, refresh]);

  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  /**
   * An edit: online only, written straight to the database. The outbox goes
   * first, so a reset or a delete is not followed by play recorded before it.
   */
  const write = useCallback(
    async (edit: (backend: Backend) => Promise<void>) => {
      const { backend, online } = live.current;
      if (!backend || !online) throw new Error("You're offline");
      setStatus({ kind: 'syncing' });
      try {
        await flush();
        await edit(backend);
      } catch (error) {
        setStatus({ kind: 'error', message: (error as Error).message });
        throw error;
      }
      await refresh();
    },
    [flush, refresh],
  );

  /** Play: recorded here first, uploaded when it can be. */
  const record = useCallback(
    async (added: { runs?: Run[]; attempts?: Attempt[] }) => {
      const { user } = live.current;
      if (!user) return;
      // Shown straight away; the stored copy follows.
      setOutbox((current) => ({
        runs: [...current.runs, ...(added.runs ?? [])],
        attempts: [...current.attempts, ...(added.attempts ?? [])],
      }));
      await addToOutbox(user.id, added);
      flush().catch((error: Error) => setStatus({ kind: 'error', message: error.message }));
    },
    [flush],
  );

  const startRun = useCallback((run: Run) => record({ runs: [run] }), [record]);
  const recordAttempt = useCallback(
    (attempt: Attempt) => record({ attempts: [attempt] }),
    [record],
  );

  const signIn = useCallback(async (mode: 'in' | 'up', email: string, password: string) => {
    if (mode === 'up') await account.signUp(email, password);
    else await account.signIn(email, password);
    const found = await account.currentUser();
    remember(found);
    setUser(found);
  }, []);

  const signOut = useCallback(async () => {
    await account.signOut();
    remember(null);
    setUser(null);
  }, []);

  return {
    user,
    library,
    /** True once the cached copy has been read, whether or not there was one. */
    loaded,
    online,
    status,
    pending: outbox.runs.length + outbox.attempts.length,
    write,
    startRun,
    recordAttempt,
    signIn,
    signOut,
  };
}
