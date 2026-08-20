import { describe, expect, it } from 'vitest';
import { importJson, isPlausibleFen } from './json';
import { importLichessCsv } from './lichess';
import { contentKey } from '../puzzle';
import { PuzzleRunner } from '../runner';

const MATE_FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';

describe('FEN plausibility', () => {
  it('accepts real positions', () => {
    expect(isPlausibleFen(MATE_FEN)).toBe(true);
    expect(isPlausibleFen('7k/5ppp/8/8/8/8/8/R5K1 w - - 0 1'), '7 + king is 8').toBe(true);
  });

  it('catches the common breakages', () => {
    expect(isPlausibleFen('6k1/5ppp/8/8/8/8/8 w - - 0 1'), 'seven ranks').toBe(false);
    expect(isPlausibleFen('6k1/5ppp/8/8/8/8/8/R5K1 x - - 0 1'), 'bad side').toBe(false);
    expect(isPlausibleFen('8k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1'), 'rank totals 10').toBe(false);
    expect(isPlausibleFen('6k1/5ppp/8/8/8/8/8/R5R1 w - - 0 1'), 'no white king').toBe(false);
    expect(isPlausibleFen('6k1/5ppp/8/8/8/8/8/R5K1x w - - 0 1'), 'bad piece letter').toBe(false);
  });
});

describe('JSON import', () => {
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
    expect(result.inserted).toHaveLength(1);
    expect(result.inserted[0]).toMatchObject({
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
    expect(result.inserted).toHaveLength(0);
    expect(result.rejected.map((r) => r.reason)).toEqual([
      'Malformed FEN',
      'Puzzle has no solution',
      'Solution line ends on an opponent move',
      'Solution contains a malformed move',
    ]);
  });

  it('reports invalid JSON rather than throwing', () => {
    const result = importJson('{ not json');
    expect(result.rejected[0].reason).toMatch(/Not valid JSON/);
  });

  it('dedupes within a single file', () => {
    const result = importJson(`
      { "puzzles": [
          { "fen": "${MATE_FEN}", "solutions": [["a1a8"]], "tags": ["a"] },
          { "fen": "6k1/5ppp/8/8/8/8/8/R5K1 w - - 5 9", "solutions": [["a1a8"]], "tags": ["b"] }
        ] }
    `);
    expect(result.inserted).toHaveLength(1);
    expect(result.updated).toHaveLength(1);
  });

  it('routes a re-import to update, not insert', () => {
    const json = `{ "puzzles": [ { "fen": "${MATE_FEN}", "solutions": [["a1a8"]] } ] }`;
    const first = importJson(json);
    const second = importJson(json, new Set(first.inserted.map(contentKey)));
    expect(second.inserted).toHaveLength(0);
    expect(second.updated).toHaveLength(1);
  });
});

describe('Lichess CSV import', () => {
  // Real shape of the dump, header included.
  const dump = [
    'PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags',
    '00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K1R w k - 0 17,f2g3 e6e7 b2b1 b3c1 b1c1 h6c1,1760,74,93,411,mate mateIn2 short,https://lichess.org/yyznGmXs/black#34,',
    '00sJ9,r3r1k1/p4ppp/2p2n2/1p6/3P1qb1/2NQR3/PPB2PP1/R1B3K1 w - - 5 18,e3g3 e8e1 g1h2 e1c1 a1c1 f4h6,2671,74,87,569,advantage attraction fork middlegame sacrifice veryLong,https://lichess.org/gyFeQsOE#35,',
  ].join('\n');

  it('parses the dump and splits off the setup move', () => {
    const result = importLichessCsv(dump);
    expect(result.inserted).toHaveLength(2);
    expect(result.rejected, 'the header is skipped, not reported').toHaveLength(0);

    expect(result.inserted[0]).toMatchObject({
      sourceId: '00sHx',
      setupMove: 'f2g3',
      rating: 1760,
      tags: ['mate', 'mateIn2', 'short'],
    });
    expect(result.inserted[0].solutions[0]).toEqual(['e6e7', 'b2b1', 'b3c1', 'b1c1', 'h6c1']);
  });

  it('filters by rating', () => {
    const result = importLichessCsv(dump, { ratingRange: [1500, 2000] });
    expect(result.inserted.map((p) => p.sourceId)).toEqual(['00sHx']);
  });

  it('filters by theme', () => {
    const result = importLichessCsv(dump, { themes: new Set(['fork']) });
    expect(result.inserted.map((p) => p.sourceId)).toEqual(['00sJ9']);
  });

  it('respects the limit', () => {
    expect(importLichessCsv(dump, { limit: 1 }).inserted).toHaveLength(1);
  });

  it('produces puzzles that run end to end', () => {
    const puzzle = importLichessCsv(dump).inserted[0];
    const runner = new PuzzleRunner(puzzle);
    const line = puzzle.solutions[0];

    for (let ply = 0; ply < line.length; ply += 2) {
      expect(runner.submit(line[ply])).toEqual({
        kind: 'correct',
        reply: ply + 1 < line.length ? line[ply + 1] : null,
        finished: ply + 2 >= line.length,
      });
    }
    expect(runner.result).toBe('solved');
  });
});

describe('multi-collection files', () => {
  // The shape produced by the 1001-exercises extraction: an array of chapters,
  // each its own collection, with book puzzle numbers as ids.
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
        { id: 58, fen: '2rrk1n1/1nQ1p2N/pB5p/6p1/qP3p2/2P4P/P3BPP1/3R2K1 w - - 0 1', solutions: [['c7d8', 'e8d8', 'd1d8']], tags: ['mateIn2'] },
      ],
    },
  ]);

  it('reads every chapter as its own group', () => {
    const result = importJson(book);
    expect(result.groups.map((group) => group.name)).toEqual(['Mate in one', 'Mate in two']);
    expect(result.groups[0].puzzles).toHaveLength(2);
    expect(result.groups[1].puzzles).toHaveLength(1);
    expect(result.inserted).toHaveLength(3);
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
