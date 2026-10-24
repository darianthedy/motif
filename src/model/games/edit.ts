import type { Uci } from '../move';
import { playFrom } from './pgn';
import type { MoveNode, ParsedGame } from './pgn';

/**
 * Changes to a game's tree. Each returns a new game and leaves the one passed
 * in as it was, so the viewer can keep showing it until the save is through.
 *
 * A place in the tree is a path: the index taken at each step from the start,
 * where 0 is always the main line. `[]` is the starting position, `[0, 0]`
 * the main line's second move, `[0, 1]` the first alternative to it.
 */
export type MovePath = number[];

/** The moves from the start to `path`, one per step. */
export function lineTo(game: ParsedGame, path: MovePath): MoveNode[] {
  const nodes: MoveNode[] = [];
  let list = game.moves;
  for (const index of path) {
    const node = list[index];
    if (!node) break;
    nodes.push(node);
    list = node.children;
  }
  return nodes;
}

export function nodeAt(game: ParsedGame, path: MovePath): MoveNode | undefined {
  return path.length ? lineTo(game, path)[path.length - 1] : undefined;
}

/** The position at `path`. */
export function fenAt(game: ParsedGame, path: MovePath): string {
  return nodeAt(game, path)?.fen ?? game.startFen;
}

/** Whether every move in `path` exists. */
export function validPath(game: ParsedGame, path: MovePath): boolean {
  return lineTo(game, path).length === path.length;
}

/** What comes after `path`. */
function nextMoves(game: ParsedGame, path: MovePath): MoveNode[] {
  return path.length ? (nodeAt(game, path)?.children ?? []) : game.moves;
}

/** One move on along the main line from `path`, or null at the end of it. */
export function forward(game: ParsedGame, path: MovePath): MovePath | null {
  return nextMoves(game, path).length ? [...path, 0] : null;
}

/**
 * Plays `move` at `path`. At the end of a line it carries the line on; in the
 * middle it starts a variation, unless it is a move already there, which is
 * simply gone to. Returns where the move is.
 */
export function playMove(
  game: ParsedGame,
  path: MovePath,
  move: Uci,
): { game: ParsedGame; path: MovePath } {
  const existing = nextMoves(game, path).findIndex((node) => node.uci === move);
  if (existing >= 0) return { game, path: [...path, existing] };

  const node = playFrom(fenAt(game, path), move);
  const next = structuredClone(game);
  const list = nextMoves(next, path);
  list.push(node);
  return { game: next, path: [...path, list.length - 1] };
}

/** Removes the move at `path` and everything after it. Returns where that leaves you. */
export function deleteFrom(game: ParsedGame, path: MovePath): { game: ParsedGame; path: MovePath } {
  if (!path.length) return { game, path };
  const next = structuredClone(game);
  const parent = path.slice(0, -1);
  nextMoves(next, parent).splice(path[path.length - 1], 1);
  return { game: next, path: parent };
}

/**
 * Makes the variation `path` is in the main line where it branches off — the
 * last step along it that was not the main line's. Returns the same move's
 * new path.
 */
export function promoteVariation(
  game: ParsedGame,
  path: MovePath,
): { game: ParsedGame; path: MovePath } {
  const at = path.findLastIndex((index) => index !== 0);
  if (at < 0) return { game, path };
  const next = structuredClone(game);
  const list = nextMoves(next, path.slice(0, at));
  const [moved] = list.splice(path[at], 1);
  list.unshift(moved);
  return { game: next, path: [...path.slice(0, at), 0, ...path.slice(at + 1)] };
}

/** Whether `path` is on the main line all the way. */
export function onMainLine(path: MovePath): boolean {
  return path.every((index) => index === 0);
}

/** Empty text clears it. A comment cannot hold a closing brace, so one is dropped. */
function cleanComment(text: string): string | undefined {
  return text.replace(/}/g, '').replace(/\s+/g, ' ').trim() || undefined;
}

/** The comment after the move at `path`; at `[]`, the note on the whole game. */
export function setComment(game: ParsedGame, path: MovePath, text: string): ParsedGame {
  const next = structuredClone(game);
  const comment = cleanComment(text);
  const target = nodeAt(next, path) ?? next;
  if (comment) target.comment = comment;
  else delete target.comment;
  return next;
}

/**
 * Headers the game keeps to itself: the starting position is what every move
 * was checked against, so it cannot be changed under them.
 */
const FIXED_HEADERS = new Set(['FEN', 'SetUp']);

/**
 * Sets headers; an empty value removes one. `Result` falls back to `*`, since
 * the movetext has to end with something.
 */
export function setHeaders(game: ParsedGame, changes: Record<string, string>): ParsedGame {
  const next = structuredClone(game);
  for (const [name, raw] of Object.entries(changes)) {
    if (FIXED_HEADERS.has(name)) continue;
    const value = raw.trim();
    if (value) next.headers[name] = value;
    else delete next.headers[name];
  }
  next.headers.Result = next.headers.Result ?? '*';
  return next;
}
