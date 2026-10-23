import { describe, expect, it } from 'vitest';
import { isValidFen } from '../board';
import { importJson } from './json';
import type { ImportResult } from './json';
import { uci } from '../move';
import { PuzzleRunner } from '../runner';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';

/** Every puzzle read, across groups. */
const read = (result: ImportResult) => result.groups.flatMap((group) => group.puzzles);

describe('FEN validity', () => {
  it('accepts real positions', () => {
    expect(isValidFen(MATE_FEN)).toBe(true);
    expect(isValidFen('7k/5ppp/8/8/8/8/8/R5K1 w - - 0 1'), '7 + king is 8').toBe(true);
  });

  it('catches the common breakages', () => {
    expect(isValidFen('6k1/5ppp/8/8/8/8/8 w - - 0 1'), 'seven ranks').toBe(false);
    expect(isValidFen('6k1/5ppp/8/8/8/8/8/R5K1 x - - 0 1'), 'bad side').toBe(false);
    expect(isValidFen('8k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1'), 'rank totals 10').toBe(false);
    expect(isValidFen('6k1/5ppp/8/8/8/8/8/R5R1 w - - 0 1'), 'no white king').toBe(false);
    expect(isValidFen('6k1/5ppp/8/8/8/8/8/R5K1x w - - 0 1'), 'bad piece letter').toBe(false);
  });
});

describe('JSON import', () => {
  it('reads the puzzle number from id, as a number or a string', () => {
    const result = importJson(
      JSON.stringify({
        puzzles: [
          { id: 187, fen: MATE_FEN, solutions: [['a1a8']] },
          { id: '12b', fen: MATE_FEN, solutions: [['a1a7']] },
        ],
      }),
    );
    expect(read(result).map((p) => p.sourceId)).toEqual(['187', '12b']);
  });

  it('imports a well-formed file', () => {
    const result = importJson(`
      { "collection": "Back-rank mates",
        "puzzles": [
          { "fen": "${MATE_FEN}",
            "solutions": [["a1a8"]],
            "tags": ["backRank"],
            "comment": "No luft.",
            "rating": 900 }
        ] }
    `);
    expect(result.collectionName).toBe('Back-rank mates');
    expect(read(result)).toHaveLength(1);
    expect(read(result)[0]).toMatchObject({
      tags: ['backRank'],
      comment: 'No luft.',
      rating: 900,
    });
  });

  it('rejects bad entries with reasons instead of dropping them', () => {
    const result = importJson(`
      { "puzzles": [
          { "fen": "not-a-fen", "solutions": [["a1a8"]] },
          { "fen": "${MATE_FEN}", "solutions": [] },
          { "fen": "${MATE_FEN}", "solutions": [["a1a8", "g8g7"]] },
          { "fen": "${MATE_FEN}", "solutions": [["a1z9"]] }
        ] }
    `);
    expect(read(result)).toHaveLength(0);
    expect(result.rejected.map((r) => r.reason)).toEqual([
      'Malformed FEN',
      'Puzzle has no solution',
      // Not rejected for its parity — an even line is allowed now — but because
      // a1a8 is mate, so the opponent has no reply to script.
      'Move g8g7 is illegal at ply 2',
      'Solution contains a malformed move',
    ]);
  });

  it('accepts a line that ends on the opponent’s forced reply', () => {
    // Rd8+ and the king has exactly one square. The idea is the check and the
    // box it puts the king in, so the line is authored to run out after the
    // reply rather than demand a follow-up move that isn't the point.
    const result = importJson(`
      { "puzzles": [
          { "fen": "6k1/5p1p/8/8/8/8/8/3R2K1 w - - 0 1",
            "solutions": [["d1d8", "g8g7"]],
            "comment": "Only square." }
        ] }
    `);
    expect(result.rejected).toEqual([]);
    expect(read(result)[0].solutions[0]).toEqual(['d1d8', 'g8g7']);

    // And it plays: one accepted move ends the puzzle, carrying the reply.
    const runner = new PuzzleRunner({
      ...read(result)[0],
      id: 'p1',
      collectionId: 'c1',
      position: 0,
      addedAt: 0,
    });
    expect(runner.submit(uci('d1d8'))).toEqual({ kind: 'correct', reply: 'g8g7', finished: true });
  });

  it('reports invalid JSON rather than throwing', () => {
    const result = importJson('{ not json');
    expect(result.rejected[0].reason).toMatch(/Not valid JSON/);
  });

  it('keeps a puzzle listed twice in one collection once, where it first appeared', () => {
    const result = importJson(`
      { "puzzles": [
          { "fen": "${MATE_FEN}", "solutions": [["a1a8"]], "tags": ["a"] },
          { "fen": "7k/5ppp/8/8/8/8/8/R6K w - - 0 1", "solutions": [["a1a8"]] },
          { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 5 9", "solutions": [["a1a8"]], "tags": ["b"] }
        ] }
    `);
    expect(read(result).map((p) => p.tags)).toEqual([['b'], []]);
  });

  it('keeps the same puzzle in two collections twice', () => {
    const entry = { fen: MATE_FEN, solutions: [['a1a8']] };
    const result = importJson(
      JSON.stringify([
        { collection: 'A', puzzles: [entry] },
        { collection: 'B', puzzles: [entry] },
      ]),
    );
    expect(result.groups.map((g) => g.puzzles.length)).toEqual([1, 1]);
  });
});

describe('multi-collection files', () => {
  // Two chapters, each its own collection, with book puzzle numbers as ids.
  // The positions are real entries from the 1001-exercises extraction and are
  // legal throughout — checked with `npm run check:external`. An earlier
  // version of this fixture was typed from memory, and its mate-in-two line
  // was illegal at ply two, which is exactly what the legality guard now
  // rejects at import.
  const book = JSON.stringify([
    {
      collection: 'Mate in one',
      puzzles: [
        { id: 1, fen: 'kr6/1p6/p7/4b3/8/8/1P4BP/R6K w - - 0 1', solutions: [['a1a6']], tags: ['mateIn1'], comment: 'The pin is mightier than the sword' },
        { id: 2, fen: 'r2B3k/5p1p/8/8/8/b7/7P/K5R1 w - - 0 1', solutions: [['d8f6']], tags: ['mateIn1'] },
      ],
    },
    {
      collection: 'Mate in two',
      puzzles: [
        { id: 58, fen: '1r1k4/2R4R/8/8/8/6pP/PPP4q/K1B5 w - - 0 1', solutions: [['c1g5', 'd8e8', 'h7h8']], tags: ['mateIn2'] },
      ],
    },
  ]);

  it('reads every chapter as its own group', () => {
    const result = importJson(book);
    expect(result.groups.map((group) => group.name)).toEqual(['Mate in one', 'Mate in two']);
    expect(result.groups[0].puzzles).toHaveLength(2);
    expect(result.groups[1].puzzles).toHaveLength(1);
    expect(read(result)).toHaveLength(3);
  });

  it('keeps the book number as the source id', () => {
    const result = importJson(book);
    expect(result.groups[0].puzzles[0].sourceId).toBe('1');
    expect(result.groups[1].puzzles[0].sourceId).toBe('58');
  });

  it('leaves collectionName unset, since one name cannot describe several', () => {
    expect(importJson(book).collectionName).toBeUndefined();
  });

  it('numbers rejections across the whole file, not per chapter', () => {
    const broken = JSON.stringify([
      { collection: 'A', puzzles: [{ fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1', solutions: [['a1a8']] }] },
      { collection: 'B', puzzles: [{ fen: 'nonsense', solutions: [['a1a8']] }] },
    ]);
    const result = importJson(broken);
    expect(result.rejected).toEqual([{ index: 1, reason: 'Malformed FEN' }]);
  });

  it('still handles a plain single-collection object', () => {
    const result = importJson(`{ "collection": "Solo", "puzzles": [ { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "solutions": [["a1a8"]] } ] }`);
    expect(result.groups).toHaveLength(1);
    expect(result.collectionName).toBe('Solo');
  });
});

describe('legality of solutions', () => {
  // Structural validation cannot see this: `a1b2` is well-formed UCI and the
  // FEN is well-formed too. Only playing the move reveals that a rook does not
  // move diagonally — and an unsolvable puzzle strands a session, because the
  // board will never accept the move the hint is pointing at.
  it('rejects a first move that is illegal in the position', () => {
    const result = importJson(
      `{ "puzzles": [ { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "solutions": [["a1b2"]] } ] }`,
    );
    expect(read(result)).toHaveLength(0);
    expect(result.rejected[0].reason).toBe('Move a1b2 is illegal at ply 1');
  });

  it('rejects a move that becomes illegal later in the line', () => {
    // Qxd8+ is fine; Kxd8 is not, because the queen is defended.
    const result = importJson(
      `{ "puzzles": [ { "fen": "2rrk1n1/1nQ1p2N/pB5p/6p1/qP3p2/2P4P/P3BPP1/3R2K1 w - - 0 1",
         "solutions": [["c7d8", "e8d8", "d1d8"]] } ] }`,
    );
    expect(read(result)).toHaveLength(0);
    expect(result.rejected[0].reason).toBe('Move e8d8 is illegal at ply 2');
  });

  it('accepts a line that is legal throughout', () => {
    const result = importJson(
      `{ "puzzles": [ { "fen": "1r1k4/2R4R/8/8/8/6pP/PPP4q/K1B5 w - - 0 1",
         "solutions": [["c1g5", "d8e8", "h7h8"]] } ] }`,
    );
    expect(read(result)).toHaveLength(1);
    expect(result.rejected).toHaveLength(0);
  });

  it('validates each line of a multi-solution puzzle', () => {
    const result = importJson(
      `{ "puzzles": [ { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
         "solutions": [["a1a8"], ["a1b2"]] } ] }`,
    );
    expect(read(result), 'one bad line rejects the puzzle').toHaveLength(0);
  });
});
