import { describe, expect, it } from 'vitest';
import { parsePgn } from './pgn';
import { lineLength, moveTable, movesFrom, startsWith } from './table';
import type { TableItem } from './table';

/** The table as text: `1. e4 e5`, `…` for a gap, `( 1... c5 )` for variations. */
const show = (items: TableItem[]) =>
  items.map((item) =>
    item.kind === 'row'
      ? `${item.number}. ${item.white?.node.san ?? '…'} ${item.black?.node.san ?? '…'}`
      : `( ${item.alternatives.map((cell) => cell.node.san).join(' | ')} )`,
  );

describe('the move table', () => {
  it('puts both sides of a move on one row', () => {
    expect(show(moveTable(parsePgn('1. e4 e5 2. Nf3 *')))).toEqual(['1. e4 e5', '2. Nf3 …']);
  });

  it("puts alternatives to Black's move after the row", () => {
    const items = moveTable(parsePgn('1. e4 e5 (1... c5 2. Nf3) (1... e6) 2. Nf3 *'));
    expect(show(items)).toEqual(['1. e4 e5', '( c5 | e6 )', '2. Nf3 …']);
    const variations = items[1] as Extract<TableItem, { kind: 'variations' }>;
    expect(variations.alternatives.map((cell) => cell.path)).toEqual([[0, 1], [0, 2]]);
    expect(variations.fen).toBe(items[0].kind === 'row' && items[0].white?.node.fen);
  });

  it("breaks the row at an alternative to White's move", () => {
    const items = moveTable(parsePgn('1. e4 (1. d4 d5) 1... e5 2. Nf3 *'));
    expect(show(items)).toEqual(['1. e4 …', '( d4 )', '1. … e5', '2. Nf3 …']);
    expect(items[2].kind === 'row' && items[2].black?.path).toEqual([0, 0]);
  });

  it('starts with a gap when Black moves first', () => {
    const game = parsePgn(
      '[SetUp "1"]\n[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n\n1... e5 2. Nf3 *',
    );
    expect(show(moveTable(game))).toEqual(['1. … e5', '2. Nf3 …']);
  });

  it('is empty for a game with no moves', () => {
    expect(moveTable(parsePgn('*'))).toEqual([]);
  });
});

describe('measuring lines', () => {
  const game = parsePgn('1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 Nc6 *');

  it('counts a line along its own main line', () => {
    expect(lineLength(game.moves[0])).toBe(4);
    expect(lineLength(game.moves[0].children[1])).toBe(3);
  });

  it('counts every move after one, variations too', () => {
    expect(movesFrom(game.moves[0])).toBe(7);
  });

  it('tells a path inside another', () => {
    expect(startsWith([0, 1, 0], [0, 1])).toBe(true);
    expect(startsWith([0, 1], [0, 1])).toBe(true);
    expect(startsWith([0, 0, 0], [0, 1])).toBe(false);
    expect(startsWith([0], [0, 1])).toBe(false);
  });
});
