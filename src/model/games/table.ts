import type { MovePath } from './edit';
import type { MoveNode, ParsedGame } from './pgn';

/** A move, and where it is. */
export interface Cell {
  node: MoveNode;
  path: MovePath;
}

export type TableItem =
  | { kind: 'row'; number: number; white: Cell | null; black: Cell | null }
  | { kind: 'variations'; fen: string; alternatives: Cell[] };

/**
 * The main line as a book's move table sets it out: a row per move number,
 * White's move beside Black's. The alternatives to a main-line move come
 * straight after its row and break it, so a White move with alternatives has
 * nothing beside it and Black's reply starts the next row on its own.
 */
export function moveTable(game: ParsedGame): TableItem[] {
  const items: TableItem[] = [];
  let row: Extract<TableItem, { kind: 'row' }> | null = null;
  let nodes = game.moves;
  let fen = game.startFen;
  let at: MovePath = [];

  while (nodes.length) {
    const [main, ...alternatives] = nodes;
    const cell = { node: main, path: [...at, 0] };
    const [, side, , , , full] = fen.split(' ');
    const number = Number(full);

    if (side === 'w') {
      row = { kind: 'row', number, white: cell, black: null };
      items.push(row);
    } else if (row && row.number === number && !row.black) {
      row.black = cell;
    } else {
      row = { kind: 'row', number, white: null, black: cell };
      items.push(row);
    }

    if (alternatives.length) {
      items.push({
        kind: 'variations',
        fen,
        alternatives: alternatives.map((node, index) => ({ node, path: [...at, index + 1] })),
      });
      row = null;
    }

    fen = main.fen;
    at = cell.path;
    nodes = main.children;
  }
  return items;
}

/** How many moves a line runs to, following its own main line. */
export function lineLength(node: MoveNode): number {
  let length = 1;
  for (let next = node.children[0]; next; next = next.children[0]) length++;
  return length;
}

/** The move and every move after it, in every line. */
export function movesFrom(node: MoveNode): number {
  return 1 + node.children.reduce((sum, child) => sum + movesFrom(child), 0);
}

/** Whether `path` is `prefix` or somewhere after it. */
export function startsWith(path: MovePath, prefix: MovePath): boolean {
  return prefix.length <= path.length && prefix.every((index, i) => path[i] === index);
}
