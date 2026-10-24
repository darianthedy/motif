import { describe, expect, it } from 'vitest';
import { uci } from '../model/move';
import type { Attempt, Library, Run } from './backend';
import { overlay } from './outbox';

const run = (scope: string, startedAt: number): Run => ({
  id: `${scope}-${startedAt}`,
  scope,
  mode: 'ordered',
  queue: ['p1'],
  startedAt,
});

const attempt = (id: string, puzzleId = 'p1'): Attempt => ({
  id,
  puzzleId,
  runId: null,
  result: 'solved',
  mistakes: 0,
  hinted: false,
  playedAt: 1,
});

function library(extra: Partial<Library> = {}): Library {
  return {
    collections: [{ id: 'c1', name: 'C', createdAt: 0 }],
    puzzles: [
      {
        id: 'p1',
        collectionId: 'c1',
        position: 0,
        fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1',
        solutions: [[uci('a1a8')]],
        tags: [],
        addedAt: 0,
      },
    ],
    runs: [],
    attempts: [],
    gameCollections: [],
    games: [],
    ...extra,
  };
}

describe('the outbox laid over the library', () => {
  it('replaces an older run in the same scope, and only an older one', () => {
    const base = library({ runs: [run('c1', 5), run('all', 5)] });
    const shown = overlay(base, { runs: [run('c1', 9), run('all', 1)], attempts: [] });
    expect(shown.runs.map((r) => r.id).sort()).toEqual(['all-5', 'c1-9']);
  });

  it('adds attempts once, and not for puzzles that are gone', () => {
    const base = library({ attempts: [attempt('a1')] });
    const shown = overlay(base, {
      runs: [],
      attempts: [attempt('a1'), attempt('a2'), attempt('a3', 'deleted')],
    });
    expect(shown.attempts.map((a) => a.id)).toEqual(['a1', 'a2']);
  });

  it('leaves the library as it is when there is nothing waiting', () => {
    const base = library();
    expect(overlay(base, { runs: [], attempts: [] })).toBe(base);
  });
});
