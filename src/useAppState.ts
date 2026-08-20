import { useCallback, useEffect, useRef, useState } from 'react';
import { loadState, requestPersistence, saveState } from './model/storage';
import type { AppState } from './model/state';

/** Debounce writes so a fast session does not queue an IndexedDB put per move. */
const SAVE_DEBOUNCE_MS = 300;

export function useAppState() {
  const [state, setState] = useState<AppState | null>(null);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    loadState().then((loaded) => {
      if (cancelled) return;
      setState(loaded);
      // Best-effort exemption from iOS's eviction of unused origins. Asked
      // once on load rather than on first write, because the prompt-free
      // version of this API only grants it for engaged origins anyway.
      void requestPersistence();
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!state) return;
    clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void saveState(state), SAVE_DEBOUNCE_MS);
    return () => clearTimeout(timer.current);
  }, [state]);

  // Flush on the way out: a debounced write can otherwise be lost when the tab
  // is backgrounded, which on iOS is most of the time.
  useEffect(() => {
    const flush = () => {
      if (state && document.visibilityState === 'hidden') void saveState(state);
    };
    document.addEventListener('visibilitychange', flush);
    return () => document.removeEventListener('visibilitychange', flush);
  }, [state]);

  const update = useCallback((fn: (current: AppState) => AppState) => {
    setState((current) => (current ? fn(current) : current));
  }, []);

  const replace = useCallback((next: AppState) => {
    setState(next);
    void saveState(next);
  }, []);

  return { state, update, replace };
}
