import { describe, expect, it } from 'vitest';
import { makeQueue, orderForGlobalDraw } from './session';

/** Deterministic stand-in for Math.random, so shuffles are reproducible. */
function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

const ids = (n: number) => Array.from({ length: n }, (_, i) => `p${i}`);

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
