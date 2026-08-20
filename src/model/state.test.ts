import { describe, expect, it } from 'vitest';
import { importJson } from './import/json';
import { contentKey } from './puzzle';
import {
  applyImport,
  deleteCollection,
  emptyState,
  failedPuzzleIds,
  recordResult,
  statsFor,
  statusOf,
} from './state';
import { parseState } from './storage';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const OTHER_FEN = '3r2k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1';

function fileWith(fen: string, extra = '') {
  return `{ "collection": "Test", "puzzles": [ { "fen": "${fen}", "solutions": [["${SOLUTION[fen]}"]]${extra} } ] }`;
}

/** The winning move differs per position; a1a8 is not legal in both. */
const SOLUTION: Record<string, string> = { [MATE_FEN]: 'a1a8', [OTHER_FEN]: 'd1d8' };

function seeded(fens: string[] = [MATE_FEN, OTHER_FEN]) {
  const puzzles = fens
    .map((fen) => `{ "fen": "${fen}", "solutions": [["${SOLUTION[fen]}"]] }`)
    .join(',');
  const result = importJson(`{ "collection": "Test", "puzzles": [${puzzles}] }`);
  return applyImport(emptyState(), result).state;
}

describe('importing into the library', () => {
  it('creates a collection and adds the puzzles', () => {
    const { state, added } = applyImport(emptyState(), importJson(fileWith(MATE_FEN)));
    expect(added).toBe(1);
    expect(state.collections).toHaveLength(1);
    expect(state.collections[0].name).toBe('Test');
    expect(state.collections[0].puzzleIds).toHaveLength(1);
  });

  it('adds nothing on a second import of the same file', () => {
    const first = applyImport(emptyState(), importJson(fileWith(MATE_FEN))).state;
    const second = applyImport(first, importJson(fileWith(MATE_FEN)));
    expect(second.added).toBe(0);
    expect(second.refreshed).toBe(1);
    expect(Object.keys(second.state.puzzles)).toHaveLength(1);
    expect(second.state.collections).toHaveLength(1);
    expect(second.state.collections[0].puzzleIds).toHaveLength(1);
  });

  it('refreshes metadata on re-import while keeping the puzzle id', () => {
    const first = applyImport(emptyState(), importJson(fileWith(MATE_FEN))).state;
    const id = Object.keys(first.puzzles)[0];

    const second = applyImport(
      first,
      importJson(fileWith(MATE_FEN, ', "comment": "Now annotated", "tags": ["backRank"]')),
    ).state;

    expect(Object.keys(second.puzzles)).toEqual([id]);
    expect(second.puzzles[id].comment).toBe('Now annotated');
    expect(second.puzzles[id].tags).toEqual(['backRank']);
  });

  it('keeps progress across a re-import', () => {
    let state = applyImport(emptyState(), importJson(fileWith(MATE_FEN))).state;
    const id = Object.keys(state.puzzles)[0];
    state = recordResult(state, id, 'solved');

    state = applyImport(state, importJson(fileWith(MATE_FEN, ', "comment": "edited"'))).state;
    expect(statusOf(state, id)).toBe('solved');
  });

  it('does not duplicate membership when importing into an existing collection', () => {
    const first = applyImport(emptyState(), importJson(fileWith(MATE_FEN))).state;
    const second = applyImport(first, importJson(fileWith(OTHER_FEN))).state;
    expect(second.collections).toHaveLength(1);
    expect(second.collections[0].puzzleIds).toHaveLength(2);
  });
});

describe('recording results', () => {
  it('marks a clean solve and stamps the first solve', () => {
    let state = seeded();
    const id = state.collections[0].puzzleIds[0];
    state = recordResult(state, id, 'solved');

    expect(statusOf(state, id)).toBe('solved');
    expect(state.progress[id].attempts).toBe(1);
    expect(state.progress[id].firstSolvedAt).toBeDefined();
  });

  it('promotes a failed puzzle when it is later solved cleanly', () => {
    let state = seeded();
    const id = state.collections[0].puzzleIds[0];

    state = recordResult(state, id, 'failed', 2);
    expect(statusOf(state, id)).toBe('failed');
    expect(failedPuzzleIds(state)).toEqual([id]);

    state = recordResult(state, id, 'solved');
    expect(statusOf(state, id)).toBe('solved');
    expect(failedPuzzleIds(state)).toEqual([]);
    expect(state.progress[id].mistakes, 'the misses stay on record').toBe(2);
    expect(state.progress[id].attempts).toBe(2);
  });

  it('demotes a solved puzzle that is later missed', () => {
    let state = seeded();
    const id = state.collections[0].puzzleIds[0];
    state = recordResult(state, id, 'solved');
    const solvedAt = state.progress[id].firstSolvedAt;

    state = recordResult(state, id, 'failed', 1);
    expect(statusOf(state, id)).toBe('failed');
    expect(state.progress[id].firstSolvedAt, 'having solved it once is not erased').toBe(solvedAt);
  });

  it('tracks recency for the global draw', () => {
    let state = seeded();
    const [first, second] = state.collections[0].puzzleIds;
    state = recordResult(state, first, 'solved');
    state = recordResult(state, second, 'solved');
    expect(state.recent[0]).toBe(second);
    expect(state.recent).toHaveLength(2);
  });
});

describe('collection stats', () => {
  it('counts by status', () => {
    let state = seeded();
    const [first, second] = state.collections[0].puzzleIds;
    state = recordResult(state, first, 'solved');
    state = recordResult(state, second, 'failed', 1);

    expect(statsFor(state, state.collections[0])).toEqual({
      total: 2,
      solved: 1,
      failed: 1,
      unseen: 0,
    });
  });
});

describe('deleting a collection', () => {
  it('removes its puzzles and their progress', () => {
    let state = seeded();
    const id = state.collections[0].puzzleIds[0];
    state = recordResult(state, id, 'solved');

    state = deleteCollection(state, state.collections[0].id);
    expect(state.collections).toHaveLength(0);
    expect(Object.keys(state.puzzles)).toHaveLength(0);
    expect(Object.keys(state.progress)).toHaveLength(0);
  });

  it('keeps puzzles that another collection still holds', () => {
    const base = applyImport(emptyState(), importJson(fileWith(MATE_FEN))).state;
    const shared = applyImport(base, importJson(fileWith(MATE_FEN)), 'Second').state;
    expect(shared.collections).toHaveLength(2);

    const after = deleteCollection(shared, shared.collections[0].id);
    expect(after.collections).toHaveLength(1);
    expect(Object.keys(after.puzzles)).toHaveLength(1);
  });
});

describe('persistence round trip', () => {
  it('survives export and re-parse', () => {
    let state = seeded();
    const id = state.collections[0].puzzleIds[0];
    state = recordResult(state, id, 'failed', 3);

    const restored = parseState(JSON.parse(JSON.stringify(state)));
    expect(Object.keys(restored.puzzles)).toHaveLength(2);
    expect(restored.collections[0].name).toBe('Test');
    expect(restored.progress[id].mistakes).toBe(3);
    expect(statusOf(restored, id)).toBe('failed');
  });

  it('drops malformed puzzles rather than losing the whole library', () => {
    const state = seeded();
    const raw = JSON.parse(JSON.stringify(state));
    raw.puzzles['broken'] = { fen: 'x', solutions: 'not-an-array' };
    raw.puzzles['bad-move'] = { fen: MATE_FEN, solutions: [['zzzz']] };

    const restored = parseState(raw);
    expect(Object.keys(restored.puzzles)).toHaveLength(2);
    expect(restored.puzzles['broken']).toBeUndefined();
    expect(restored.puzzles['bad-move']).toBeUndefined();
  });

  it('drops collection references to puzzles that did not survive', () => {
    const raw = JSON.parse(JSON.stringify(seeded()));
    const [firstId] = Object.keys(raw.puzzles);
    delete raw.puzzles[firstId];

    const restored = parseState(raw);
    expect(restored.collections[0].puzzleIds).not.toContain(firstId);
    expect(restored.collections[0].puzzleIds).toHaveLength(1);
  });

  it('rejects a blob that is not an object', () => {
    expect(() => parseState('nope')).toThrow();
  });

  it('reads an empty store as an empty library', () => {
    expect(parseState({}).collections).toEqual([]);
    expect(Object.keys(parseState({}).puzzles)).toHaveLength(0);
  });
});

describe('content identity', () => {
  it('is stable across a JSON round trip', () => {
    const state = seeded();
    const puzzle = Object.values(state.puzzles)[0];
    const restored = parseState(JSON.parse(JSON.stringify(state)));
    expect(contentKey(restored.puzzles[puzzle.id])).toBe(contentKey(puzzle));
  });
});

describe('importing a multi-chapter file', () => {
  const book = JSON.stringify([
    { collection: 'Chapter one', puzzles: [{ fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1', solutions: [['a1a8']] }] },
    { collection: 'Chapter two', puzzles: [{ fen: '3r2k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1', solutions: [['d1d8']] }] },
  ]);

  it('creates one collection per chapter', () => {
    const { state, added, collections } = applyImport(emptyState(), importJson(book));
    expect(added).toBe(2);
    expect(collections).toBe(2);
    expect(state.collections.map((c) => c.name)).toEqual(['Chapter one', 'Chapter two']);
    expect(state.collections[0].puzzleIds).toHaveLength(1);
    expect(state.collections[1].puzzleIds).toHaveLength(1);
  });

  it('does not let a supplied name collapse the chapters together', () => {
    const { state } = applyImport(emptyState(), importJson(book), 'Everything');
    expect(state.collections.map((c) => c.name)).toEqual(['Chapter one', 'Chapter two']);
  });

  it('is idempotent across the whole file', () => {
    const first = applyImport(emptyState(), importJson(book)).state;
    const second = applyImport(first, importJson(book));
    expect(second.added).toBe(0);
    expect(second.refreshed).toBe(2);
    expect(second.state.collections).toHaveLength(2);
    expect(Object.keys(second.state.puzzles)).toHaveLength(2);
  });
});
