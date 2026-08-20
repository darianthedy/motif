import { describe, expect, it } from 'vitest';
import {
  completeCurrent,
  isFinished,
  makeQueue,
  MAX_RETRIES,
  orderForGlobalDraw,
  progress,
  reconcile,
  RETRY_GAP,
  startSession,
} from './session';
import type { SessionState } from './session';

/** Deterministic stand-in for Math.random, so shuffles are reproducible. */
function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

const ids = (n: number) => Array.from({ length: n }, (_, i) => `p${i}`);

/** Solve every puzzle served until the session ends, recording the order. */
function runAllSolved(start: SessionState): string[] {
  const served: string[] = [];
  let session = start;
  while (!isFinished(session)) {
    served.push(session.current!);
    session = completeCurrent(session, 'solved');
  }
  return served;
}

describe('queue building', () => {
  it('preserves insertion order in ordered mode', () => {
    expect(makeQueue('ordered', ids(5), seeded(1))).toEqual(ids(5));
  });

  it('shuffles into a permutation with no repeats', () => {
    const list = ids(50);
    const queue = makeQueue('randomInCollection', list, seeded(42));
    expect(queue).toHaveLength(50);
    expect(new Set(queue)).toEqual(new Set(list));
    expect(queue).not.toEqual(list);
  });
});

describe('session progression', () => {
  it('serves every puzzle once when nothing is missed', () => {
    const session = startSession('ordered', 'c1', ids(4), seeded(1));
    expect(runAllSolved(session)).toEqual(ids(4));
  });

  it('reports progress against the original queue', () => {
    let session = startSession('ordered', 'c1', ids(4), seeded(1));
    expect(progress(session)).toBe(0);
    session = completeCurrent(session, 'solved');
    expect(progress(session)).toBe(0.25);
  });

  it('finishes with the current puzzle cleared', () => {
    const session = completeCurrent(
      startSession('ordered', 'c1', ['only'], seeded(1)),
      'solved',
    );
    expect(isFinished(session)).toBe(true);
    expect(session.current).toBeNull();
    expect(progress(session)).toBe(1);
  });

  it('handles an empty collection without hanging', () => {
    const session = startSession('ordered', 'c1', [], seeded(1));
    expect(isFinished(session)).toBe(true);
    expect(progress(session)).toBe(1);
  });
});

describe('retrying missed puzzles', () => {
  it('re-serves a missed puzzle after a gap rather than immediately', () => {
    let session = startSession('ordered', 'c1', ids(6), seeded(1));
    const served: string[] = [];

    // Miss the first puzzle, solve everything after it.
    while (!isFinished(session)) {
      served.push(session.current!);
      const result = served.length === 1 ? 'failed' : 'solved';
      session = completeCurrent(session, result);
    }

    expect(served[0]).toBe('p0');
    const retryAt = served.indexOf('p0', 1);
    expect(retryAt, 'the missed puzzle comes back').toBeGreaterThan(0);
    expect(
      served.slice(1, retryAt),
      'with exactly RETRY_GAP other puzzles in between',
    ).toHaveLength(RETRY_GAP);
    expect(served.filter((id) => id === 'p0')).toHaveLength(2);
  });

  it('marks a puzzle solved when the retry is clean, while keeping the miss on record', () => {
    let session = startSession('ordered', 'c1', ids(6), seeded(1));
    session = completeCurrent(session, 'failed');
    while (session.current !== 'p0' && !isFinished(session)) {
      session = completeCurrent(session, 'solved');
    }
    expect(session.current).toBe('p0');
    session = completeCurrent(session, 'solved');

    expect(session.solvedIds).toContain('p0');
    expect(session.failedIds).toContain('p0');
  });

  it('caps the retry backlog so a bad run cannot spiral', () => {
    let session = startSession('ordered', 'c1', ids(40), seeded(7));
    for (let i = 0; i < 30 && !isFinished(session); i++) {
      session = completeCurrent(session, 'failed');
    }
    expect(session.retries.length).toBeLessThanOrEqual(MAX_RETRIES);
  });

  it('drains the backlog before ending rather than stopping with retries owed', () => {
    let session = startSession('ordered', 'c1', ids(2), seeded(1));
    session = completeCurrent(session, 'failed'); // p0 owed a retry
    session = completeCurrent(session, 'solved'); // p1 done, queue exhausted
    expect(isFinished(session)).toBe(false);
    expect(session.current).toBe('p0');
  });
});

describe('resume and reconcile', () => {
  it('survives a serialization round trip mid-session', () => {
    let session = startSession('randomInCollection', 'c1', ids(4), seeded(3));
    session = completeCurrent(session, 'solved');

    const resumed: SessionState = JSON.parse(JSON.stringify(session));
    expect(resumed.current).toBe(session.current);
    expect(resumed.queue).toEqual(session.queue);
  });

  it('drops deleted puzzles and keeps the current one', () => {
    const session = startSession('ordered', 'c1', ids(5), seeded(1));
    const trimmed = reconcile(session, new Set(['p0', 'p2', 'p3', 'p4']));
    expect(trimmed.queue).toEqual(['p0', 'p2', 'p3', 'p4']);
    expect(trimmed.current).toBe('p0');
  });

  it('moves on when the current puzzle itself is deleted', () => {
    let session = startSession('ordered', 'c1', ids(5), seeded(1));
    session = completeCurrent(session, 'solved'); // now on p1
    expect(session.current).toBe('p1');

    const trimmed = reconcile(session, new Set(['p0', 'p2', 'p3', 'p4']));
    expect(trimmed.current).toBe('p2');
  });

  it('forgets retries for puzzles that no longer exist', () => {
    let session = startSession('ordered', 'c1', ids(5), seeded(1));
    session = completeCurrent(session, 'failed');
    expect(session.retries).toHaveLength(1);

    const trimmed = reconcile(session, new Set(['p1', 'p2', 'p3', 'p4']));
    expect(trimmed.retries).toHaveLength(0);
  });
});

describe('global draw', () => {
  it('puts recently seen puzzles last without excluding them', () => {
    const order = orderForGlobalDraw(ids(6), ['p0', 'p1'], seeded(5));
    expect(order).toHaveLength(6);
    expect(new Set(order)).toEqual(new Set(ids(6)));
    expect(order.slice(-2).sort()).toEqual(['p0', 'p1']);
  });

  it('still returns everything when the whole library is recent', () => {
    const order = orderForGlobalDraw(ids(3), ids(3), seeded(5));
    expect(new Set(order)).toEqual(new Set(ids(3)));
  });
});
