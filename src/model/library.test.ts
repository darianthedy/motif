import { describe, expect, it } from 'vitest';
import { uci } from './move';
import { planImport } from './library';
import type { Puzzle, PuzzleContent } from './puzzle';

const FEN = '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1';
const content = (move: string, comment?: string): PuzzleContent => ({
  fen: FEN,
  solutions: [[uci(move)]],
  tags: [],
  comment,
});

describe('planning an import into a collection', () => {
  it('numbers a new collection in file order', () => {
    const { puzzles, added } = planImport([], [content('a1a8'), content('a1a7')], 'c1');
    expect(puzzles.map((p) => [p.collectionId, p.position])).toEqual([
      ['c1', 0],
      ['c1', 1],
    ]);
    expect(added).toBe(2);
  });

  it('keeps the place of a puzzle the collection already has, and appends the rest', () => {
    const existing: Puzzle[] = [
      { ...content('a1a7'), id: 'x', collectionId: 'c1', position: 0, addedAt: 0 },
      { ...content('a1a6'), id: 'y', collectionId: 'c1', position: 4, addedAt: 0 },
    ];
    const { puzzles, added } = planImport(
      existing,
      [content('a1a8'), content('a1a6', 'edited')],
      'c1',
    );
    expect(puzzles.map((p) => [p.solutions[0][0], p.position, p.comment])).toEqual([
      ['a1a8', 5, undefined],
      ['a1a6', 4, 'edited'],
    ]);
    expect(added).toBe(1);
  });
});
