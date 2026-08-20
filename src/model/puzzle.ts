import type { Uci } from './move';

export type Side = 'w' | 'b';

/** Whether a puzzle has ever been completed, and how. */
export type PuzzleStatus = 'unseen' | 'solved' | 'failed';

export interface Puzzle {
  id: string;
  /** Full FEN of the position *before* `setupMove` is played. */
  fen: string;
  /**
   * A move the opponent plays into the position before the solver's turn.
   *
   * Lichess stores puzzles this way — the FEN is one ply early and the first
   * listed move is the opponent's. Rather than mutate the FEN at import time,
   * the ply is kept as data and animated by the UI before the clock starts,
   * which is also better to watch. Hand-written puzzles leave it undefined.
   */
  setupMove?: Uci;
  /**
   * Each solution is an ordered line alternating solver move, opponent reply,
   * solver move, ... Lines may share prefixes; the trie merges them.
   */
  solutions: Uci[][];
  /** The idea behind the puzzle. Never rendered while solving — it's a spoiler. */
  tags: string[];
  /** Free-form note. Also never rendered while solving. */
  comment?: string;
  /** Upstream identifier, e.g. a Lichess puzzle id. Not a dedupe key. */
  sourceId?: string;
  rating?: number;
  addedAt: number;
}

/** Progress is global, not per-collection: solving a puzzle anywhere counts. */
export interface Progress {
  puzzleId: string;
  status: PuzzleStatus;
  attempts: number;
  /** Cumulative incorrect moves across every attempt. Never reset. */
  mistakes: number;
  lastAttemptAt?: number;
  firstSolvedAt?: number;
}

export interface Collection {
  id: string;
  name: string;
  createdAt: number;
  /** Puzzle ids in insertion order. Order is the collection's own, not global. */
  puzzleIds: string[];
}

export function newProgress(puzzleId: string): Progress {
  return { puzzleId, status: 'unseen', attempts: 0, mistakes: 0 };
}

/**
 * FEN reduced to the fields that define the position: placement, side to move,
 * castling rights, en passant square. Halfmove and fullmove counters are
 * dropped — two exports of the same puzzle that disagree only on move number
 * are the same puzzle.
 */
export function normalizeFen(fen: string): string {
  return fen.trim().split(/\s+/).slice(0, 4).join(' ');
}

/**
 * Identity for import dedupe: the position plus what counts as solving it.
 *
 * A canonical string rather than a digest. It is longer, but it cannot collide,
 * it is legible in a store dump, and at these volumes the cost is irrelevant.
 * Tags, comment, rating and source are excluded on purpose, so re-importing a
 * file with edited metadata updates the existing puzzle instead of forking it.
 */
export function contentKey(
  puzzle: Pick<Puzzle, 'fen' | 'setupMove' | 'solutions'>,
): string {
  // Solution order must not affect identity: the same two lines listed in the
  // other order are the same puzzle.
  const lines = puzzle.solutions
    .map((line) => line.join(' '))
    .sort()
    .join('|');
  return `${normalizeFen(puzzle.fen)}/${puzzle.setupMove ?? '-'}/${lines}`;
}

/** Side the solver plays, flipped when a setup move is played in first. */
export function solverSide(puzzle: Pick<Puzzle, 'fen' | 'setupMove'>): Side {
  const fenSide: Side = normalizeFen(puzzle.fen).split(' ')[1] === 'b' ? 'b' : 'w';
  if (!puzzle.setupMove) return fenSide;
  return fenSide === 'w' ? 'b' : 'w';
}
